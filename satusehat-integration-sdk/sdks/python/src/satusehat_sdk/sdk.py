from __future__ import annotations
import json
import random
import threading
import socket
import time
import urllib.error
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
from .auth import TokenProvider
from .config import SatusehatConfig
from .errors import classify_http
from .http import FhirClient
from .models import EventStatus, FhirResponse
from .queue import SQLiteQueue

class _RateLimiter:
    def __init__(self, rpm: int):
        self.interval = 60.0 / rpm
        self.last = 0.0
        self.lock = threading.Lock()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            wait = self.last + self.interval - now
            if wait > 0:
                time.sleep(wait)
            self.last = time.monotonic()

class SatusehatSdk:
    def __init__(self, config: SatusehatConfig):
        self.config = config
        self.tokens = TokenProvider(config)
        self.fhir = FhirClient(config, self.tokens)
        self.queue = SQLiteQueue(config.queue_path)
        self.rate = _RateLimiter(config.rate_limit_rpm)

    def close(self):
        self.queue.close()

    def enqueue(self, operation: str, resource_type: str, resource_id: str | None = None, payload=None) -> str:
        return self.queue.enqueue(self.config.organization_id, operation, resource_type, resource_id, payload)

    def request(self, operation: str, resource_type: str, resource_id: str | None = None, payload=None) -> FhirResponse:
        last = None
        for attempt in range(1, self.config.max_retries + 1):
            self.rate.wait()
            try:
                response = self.fhir.request_once(operation, resource_type, resource_id, payload)
                if response.status_code == 401:
                    self.tokens.invalidate()
                category, retryable = classify_http(response.status_code)
                if not retryable or attempt >= self.config.max_retries:
                    return response
                self._sleep_backoff(attempt, response.headers.get("Retry-After"))
                last = response
            except (urllib.error.URLError, TimeoutError, socket.timeout, OSError):
                if attempt >= self.config.max_retries:
                    raise
                self._sleep_backoff(attempt, None)
        assert last is not None
        return last

    def process_once(self, limit: int = 20) -> int:
        processed = 0
        for row in self.queue.ready(limit):
            processed += 1
            event_id = row["event_id"]
            attempt = self.queue.mark_processing(event_id)
            payload = json.loads(row["payload_json"]) if row["payload_json"] else None
            self.rate.wait()
            try:
                response = self.fhir.request_once(row["operation"], row["resource_type"], row["resource_id"], payload)
                self._apply_response(event_id, attempt, response)
            except (urllib.error.URLError, TimeoutError, socket.timeout, OSError) as exc:
                self._schedule_retry(event_id, attempt, "transport_error", str(exc), None, None)
            except Exception as exc:
                # Includes OAuth failures; do not spin aggressively.
                self._schedule_retry(event_id, attempt, "authentication_or_client_error", str(exc), None, None)
        return processed

    def _apply_response(self, event_id: str, attempt: int, response: FhirResponse):
        status = response.status_code
        category, retryable = classify_http(status)
        if 200 <= status <= 299:
            self.queue.complete(event_id, EventStatus.SUCCESS, status)
            return
        if status == 401:
            self.tokens.invalidate()
        if retryable:
            target = EventStatus.RATE_LIMITED if status == 429 else EventStatus.RETRYING
            self._schedule_retry(event_id, attempt, category, response.body, status, response.headers.get("Retry-After"), target)
            return
        self.queue.complete(event_id, EventStatus.WAITING_FOR_CORRECTION, status, category, response.body)

    def _schedule_retry(self, event_id: str, attempt: int, category: str, message: str, http_status: int | None, retry_after: str | None, target: EventStatus = EventStatus.RETRYING):
        if attempt >= self.config.max_retries:
            self.queue.complete(event_id, EventStatus.DEAD_LETTER, http_status, category, message)
            return
        delay = self._backoff_seconds(attempt, retry_after)
        next_time = datetime.now(timezone.utc) + timedelta(seconds=delay)
        next_iso = next_time.isoformat().replace("+00:00", "Z")
        self.queue.complete(event_id, target, http_status, category, message, next_iso)

    def _sleep_backoff(self, attempt: int, retry_after: str | None):
        time.sleep(self._backoff_seconds(attempt, retry_after))

    def _backoff_seconds(self, attempt: int, retry_after: str | None) -> float:
        if retry_after:
            try:
                return max(0.0, float(retry_after))
            except ValueError:
                try:
                    when = parsedate_to_datetime(retry_after)
                    return max(0.0, (when - datetime.now(when.tzinfo or timezone.utc)).total_seconds())
                except Exception:
                    pass
        base_ms = min(self.config.max_backoff_ms, self.config.initial_backoff_ms * (2 ** max(0, attempt - 1)))
        return (base_ms + random.uniform(0, min(1000, base_ms * 0.2))) / 1000.0

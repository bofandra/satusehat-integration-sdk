from __future__ import annotations
import json
import threading
import time
import urllib.parse
import urllib.request
import urllib.error
from .config import SatusehatConfig

class TokenProvider:
    def __init__(self, config: SatusehatConfig):
        self.config = config
        self._token: str | None = None
        self._expires_at = 0.0
        self._lock = threading.Lock()

    def invalidate(self) -> None:
        with self._lock:
            self._token = None
            self._expires_at = 0.0

    def get_token(self) -> str:
        with self._lock:
            now = time.time()
            if self._token and now < self._expires_at - 60:
                return self._token
            data = urllib.parse.urlencode({
                "client_id": self.config.client_id,
                "client_secret": self.config.client_secret,
            }).encode()
            url = self.config.oauth_base_url + "/accesstoken?grant_type=client_credentials"
            req = urllib.request.Request(url, data=data, method="POST", headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
            })
            try:
                with urllib.request.urlopen(req, timeout=self.config.timeout_seconds) as resp:
                    raw = resp.read().decode("utf-8")
            except urllib.error.HTTPError as exc:
                body = exc.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"OAuth HTTP {exc.code}: {body[:1000]}") from exc
            obj = json.loads(raw)
            token = obj.get("access_token")
            if not token:
                raise RuntimeError("OAuth response does not contain access_token")
            expires = int(obj.get("expires_in", 300))
            self._token = token
            self._expires_at = now + expires
            return token

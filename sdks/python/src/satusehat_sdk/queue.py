from __future__ import annotations
import json
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from .models import EventStatus

DDL = """
CREATE TABLE IF NOT EXISTS integration_events (
  event_id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL,
  idempotency_key TEXT,
  operation TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT,
  payload_json TEXT,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 0,
  http_status INTEGER,
  error_category TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  next_retry_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_integration_events_ready
ON integration_events(status, next_retry_at, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency
ON integration_events(organization_id, idempotency_key)
WHERE idempotency_key IS NOT NULL;
"""

def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

class SQLiteQueue:
    def __init__(self, path: str, processing_timeout_seconds: int = 300):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.processing_timeout_seconds = processing_timeout_seconds
        self.db = sqlite3.connect(path, timeout=30, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(DDL)
        self._migrate()
        self.db.commit()

    def close(self):
        self.db.close()

    def _migrate(self) -> None:
        columns = {row["name"] for row in self.db.execute("PRAGMA table_info(integration_events)").fetchall()}
        if "idempotency_key" not in columns:
            self.db.execute("ALTER TABLE integration_events ADD COLUMN idempotency_key TEXT")
        self.db.execute("""CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency
            ON integration_events(organization_id, idempotency_key)
            WHERE idempotency_key IS NOT NULL""")

    def enqueue(self, organization_id: str, operation: str, resource_type: str, resource_id: str | None, payload, idempotency_key: str | None = None) -> str:
        operation = operation.upper()
        if operation not in {"GET", "POST", "PUT", "PATCH"}:
            raise ValueError("unsupported operation")
        if operation in {"PUT", "PATCH"} and not resource_id:
            raise ValueError("resource_id is required for PUT/PATCH")
        idempotency_key = idempotency_key.strip() if idempotency_key else None
        if idempotency_key:
            existing = self.db.execute(
                "SELECT event_id FROM integration_events WHERE organization_id=? AND idempotency_key=?",
                (organization_id, idempotency_key),
            ).fetchone()
            if existing:
                return str(existing["event_id"])
        event_id = str(uuid.uuid4())
        now = utcnow()
        payload_json = json.dumps(payload, separators=(",", ":")) if payload is not None else None
        try:
            self.db.execute("""INSERT INTO integration_events
                (event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,0,?,?)""",
                (event_id, organization_id, idempotency_key, operation, resource_type, resource_id, payload_json, EventStatus.QUEUED.value, now, now))
        except sqlite3.IntegrityError:
            existing = self.db.execute(
                "SELECT event_id FROM integration_events WHERE organization_id=? AND idempotency_key=?",
                (organization_id, idempotency_key),
            ).fetchone()
            if existing:
                return str(existing["event_id"])
            raise
        self.db.commit()
        return event_id

    def ready(self, limit: int):
        now = utcnow()
        return self.db.execute("""SELECT * FROM integration_events
            WHERE (
                status IN ('QUEUED','RETRYING','RATE_LIMITED')
                AND (next_retry_at IS NULL OR next_retry_at <= ?)
            ) OR (
                status = 'PROCESSING'
                AND next_retry_at IS NOT NULL
                AND next_retry_at <= ?
            )
            ORDER BY created_at LIMIT ?""", (now, now, limit)).fetchall()

    def mark_processing(self, event_id: str) -> int:
        now = utcnow()
        lease_until = (
            datetime.now(timezone.utc) + timedelta(seconds=self.processing_timeout_seconds)
        ).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        self.db.execute(
            "UPDATE integration_events SET status='PROCESSING', attempt=attempt+1, updated_at=?, next_retry_at=? WHERE event_id=?",
            (now, lease_until, event_id),
        )
        self.db.commit()
        row = self.db.execute("SELECT attempt FROM integration_events WHERE event_id=?", (event_id,)).fetchone()
        return int(row["attempt"])

    def complete(self, event_id: str, status: EventStatus, http_status: int | None = None, category: str | None = None, message: str | None = None, next_retry_at: str | None = None):
        self.db.execute("""UPDATE integration_events SET status=?, http_status=?, error_category=?, error_message=?,
            updated_at=?, next_retry_at=? WHERE event_id=?""",
            (status.value, http_status, category, message[:2000] if message else None, utcnow(), next_retry_at, event_id))
        self.db.commit()

    def get(self, event_id: str):
        return self.db.execute("SELECT * FROM integration_events WHERE event_id=?", (event_id,)).fetchone()

    def stats(self) -> dict[str, int]:
        out = {status.value: 0 for status in EventStatus}
        rows = self.db.execute("SELECT status, COUNT(*) AS n FROM integration_events GROUP BY status").fetchall()
        for row in rows:
            out[str(row["status"])] = int(row["n"])
        return out

    def dead_letters(self, limit: int = 50) -> list[dict]:
        rows = self.db.execute(
            "SELECT * FROM integration_events WHERE status=? ORDER BY updated_at DESC LIMIT ?",
            (EventStatus.DEAD_LETTER.value, limit),
        ).fetchall()
        return [dict(row) for row in rows]

    def requeue(self, event_id: str) -> bool:
        cur = self.db.execute("""UPDATE integration_events
            SET status=?, attempt=0, http_status=NULL, error_category=NULL, error_message=NULL,
                updated_at=?, next_retry_at=NULL
            WHERE event_id=? AND status IN (?,?,?)""",
            (
                EventStatus.QUEUED.value,
                utcnow(),
                event_id,
                EventStatus.DEAD_LETTER.value,
                EventStatus.WAITING_FOR_CORRECTION.value,
                EventStatus.CANCELLED.value,
            ),
        )
        self.db.commit()
        return cur.rowcount > 0

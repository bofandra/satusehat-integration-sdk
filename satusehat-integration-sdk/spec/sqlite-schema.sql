PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS integration_events (
  event_id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK(operation IN ('GET','POST','PUT','PATCH')),
  resource_type TEXT NOT NULL,
  resource_id TEXT,
  payload_json TEXT,
  status TEXT NOT NULL CHECK(status IN (
    'QUEUED','PROCESSING','SUCCESS','WAITING_FOR_CORRECTION',
    'RATE_LIMITED','RETRYING','DEAD_LETTER','CANCELLED'
  )),
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

CREATE INDEX IF NOT EXISTS idx_integration_events_resource
ON integration_events(resource_type, resource_id);

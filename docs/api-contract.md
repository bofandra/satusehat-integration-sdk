# Common SDK API Contract

Each language exposes equivalent concepts even when naming follows ecosystem conventions.

## Config

- environment
- client_id
- client_secret
- organization_id
- queue_path
- timeout_seconds
- rate_limit_rpm
- max_retries
- initial_backoff_ms
- max_backoff_ms
- optional oauth_base_url override
- optional fhir_base_url override

## SDK

### enqueue(operation, resource_type, resource_id?, payload?) -> event_id
Persists a durable event and returns immediately.

### processOnce(limit) -> processed_count
Processes due queue records.

### request(...)
Synchronous low-level FHIR request.

### close()
Closes local resources.

## Queue statuses

`QUEUED`, `PROCESSING`, `SUCCESS`, `WAITING_FOR_CORRECTION`, `RATE_LIMITED`, `RETRYING`, `DEAD_LETTER`, `CANCELLED`.

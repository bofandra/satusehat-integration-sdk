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
- processing_timeout_seconds
- initial_backoff_ms
- max_backoff_ms
- optional oauth_base_url override
- optional fhir_base_url override

## SDK

### enqueue(operation, resource_type, resource_id?, payload?, idempotency_key?) -> event_id
Persists a durable event and returns immediately.

If `idempotency_key` is provided, the SDK returns the existing `event_id` for the same organization/key instead of inserting a duplicate queue row. Go exposes this as `EnqueueIdempotent(...)` because Go does not support optional parameters.

### processOnce(limit) -> processed_count
Processes due queue records.

### queueStats() -> counts_by_status
Returns queue counts grouped by event status.

### deadLetters(limit) -> queue_records
Returns the newest `DEAD_LETTER` events for operator review.

### requeue(event_id) -> boolean
Moves a `DEAD_LETTER`, `WAITING_FOR_CORRECTION`, or `CANCELLED` event back to `QUEUED` after the operator fixes the root cause.

### request(...)
Synchronous low-level FHIR request.

### close()
Closes local resources.

## Queue statuses

`QUEUED`, `PROCESSING`, `SUCCESS`, `WAITING_FOR_CORRECTION`, `RATE_LIMITED`, `RETRYING`, `DEAD_LETTER`, `CANCELLED`.

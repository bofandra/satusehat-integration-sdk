# Security Design

## Secrets

Credentials are constructor/environment inputs and are never stored in the queue table. Tokens are memory-cache only in this reference implementation.

## PHI/PII

FHIR payloads may contain PHI/PII. The SDK does not export telemetry by default. Operational logging should prefer:

- event_id;
- organization_id;
- resource_type;
- resource_id;
- HTTP status;
- error category;
- latency/attempt.

Avoid body logging.

## SQLite

SQLite is selected for zero-infrastructure adoption, not because it provides encryption by itself. Protect the volume using operating-system or disk encryption. Enterprise deployments can implement a queue adapter backed by PostgreSQL/message broker.

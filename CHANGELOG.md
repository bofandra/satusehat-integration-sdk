# Changelog

## Unreleased
- Ruby reference SDK added with OAuth2, FHIR HTTP, canonical SQLite queue schema, idempotent enqueue, retry/backoff, rate limiting, dead-letter/requeue primitives, and Minitest coverage.

## 0.2.0 - 2026-08-23
- language-neutral Integration Console and responsive dashboard;
- correction worklist from shared SQLite queue;
- durable client webhook outbox with HMAC signature and independent retries;
- OperationOutcome parsing for actionable error metadata;
- source/correlation context API;
- corrected-data API creates a new `QUEUED` revision and preserves the failed event;
- event history and notification tables;
- monitoring APIs do not expose FHIR payload by default;
- common notification/correction schemas;
- repository metadata updated to `github.com/bofandra/satusehat-integration-sdk`.

## 0.1.0 - 2026-08-12
Initial multi-language reference SDK with OAuth2, FHIR client, SQLite queue, worker, idempotency, retry/backoff, rate limiting, and dead-letter/requeue primitives.

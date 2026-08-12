# Architecture

## Recommended path

```text
Clinical transaction
      |
      +-- commit application database
      |
      +-- write transactional outbox (same DB transaction)
                    |
                    v
             Outbox publisher
                    |
                    v
           SDK SQLite queue
                    |
                    v
                 Worker
                    |
                    v
             SATUSEHAT API
```

The SDK queue is durable, but it cannot make a different SIMRS database transaction atomic. A transactional outbox closes the gap between local clinical commit and enqueue.

## Components

### Config
Resolves sandbox/production URLs and tuning parameters.

### Token Provider
Caches OAuth token until shortly before expiry. On 401 it invalidates the cache and a subsequent attempt obtains a new token.

### FHIR Client
Serializes JSON, adds Bearer token, calls SATUSEHAT, and returns structured response/error data.

### Queue
SQLite persistence with common DDL. The default SQLite implementation should be treated as a **single-active-worker queue per database file**. Large, multi-worker, or HA deployments should replace it with a shared store/queue adapter that supports atomic claiming/leases.

### Worker
Claims ready events, executes a FHIR request, classifies the result, and updates event status.

### Rate Limiter
Local pacing based on configured requests/minute. It is deliberately simple and does not replace API gateway policies.

## Failure Domains

- SATUSEHAT unavailable: events remain queued/retrying.
- Network unavailable: retry with backoff.
- Invalid clinical data: waiting for correction.
- Invalid credentials: do not loop aggressively; investigate configuration.
- Process restart: queued events persist in SQLite.
- SQLite unavailable/full disk: enqueue fails; application must surface this as an integration infrastructure problem.

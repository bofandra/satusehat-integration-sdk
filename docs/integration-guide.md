# Integration Guide

## 1. Choose synchronous vs asynchronous

Use asynchronous enqueue for clinical submissions. Use synchronous requests for search/read operations where the caller needs an immediate result.

## 2. Keep local source IDs

Maintain a mapping between local entity ID and SATUSEHAT FHIR resource ID. PUT/PATCH require the target resource ID.

## 3. Use idempotency keys

Pass a stable idempotency key when enqueueing from a facility source record. If a publisher retries after a crash, the SDK returns the existing `event_id` instead of creating a duplicate SATUSEHAT submission.

Example key pattern:

```text
encounter:{local_visit_id}:create
condition:{local_diagnosis_id}:upsert
observation:{local_order_id}:{loinc_code}:final
```

## 4. Use an outbox

In the same transaction that modifies the local clinical record, write an outbox record. A publisher can retry calling SDK enqueue safely.

## 5. Run a worker

Run `processOnce` continuously or through a scheduler. For high throughput, isolate the worker process from the main web process.

## 6. Monitor queue health

Minimum metrics:

- count by status;
- oldest QUEUED/RETRYING event age;
- success rate;
- error category distribution;
- dead-letter count.

The SDK exposes queue stats and dead-letter listing helpers for this.

## 7. Reconciliation

Periodically compare local source records with SUCCESS integration events and/or SATUSEHAT resource IDs. Queue success means HTTP success; business reconciliation may require additional checks depending on the use case.

## Example transactional outbox in SIMRS

The table below lives in the **SIMRS database**, not in the SDK SQLite database.

```sql
CREATE TABLE satusehat_outbox (
  outbox_id VARCHAR(64) PRIMARY KEY,
  source_table VARCHAR(100) NOT NULL,
  source_id VARCHAR(100) NOT NULL,
  operation VARCHAR(10) NOT NULL,
  resource_type VARCHAR(50) NOT NULL,
  resource_id VARCHAR(100),
  payload_json TEXT NOT NULL,
  idempotency_key VARCHAR(200) NOT NULL,
  published_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL,
  UNIQUE(idempotency_key)
);
```

Application transaction:

```text
BEGIN
  save/update clinical record
  insert satusehat_outbox
COMMIT
```

Publisher:

```text
select unpublished outbox rows
    -> SDK enqueue with idempotency_key
    -> receive event_id
    -> mark outbox row published
```

The unique key must be designed according to the application's business lifecycle; the example above is illustrative and may be too strict when one source row legitimately generates multiple updates.

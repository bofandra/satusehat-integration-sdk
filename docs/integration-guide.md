# Integration Guide

## 1. Choose synchronous vs asynchronous

Use asynchronous enqueue for clinical submissions. Use synchronous requests for search/read operations where the caller needs an immediate result.

## 2. Keep local source IDs

Maintain a mapping between local entity ID and SATUSEHAT FHIR resource ID. PUT/PATCH require the target resource ID.

## 3. Use an outbox

In the same transaction that modifies the local clinical record, write an outbox record. A publisher can retry calling SDK enqueue safely.

## 4. Run a worker

Run `processOnce` continuously or through a scheduler. For high throughput, isolate the worker process from the main web process.

## 5. Monitor queue health

Minimum metrics:

- count by status;
- oldest QUEUED/RETRYING event age;
- success rate;
- error category distribution;
- dead-letter count.

## 6. Reconciliation

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
  published_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL,
  UNIQUE(source_table, source_id, operation, resource_type)
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
    -> SDK enqueue
    -> receive event_id
    -> mark outbox row published
```

The unique key must be designed according to the application's business lifecycle; the example above is illustrative and may be too strict when one source row legitimately generates multiple updates.

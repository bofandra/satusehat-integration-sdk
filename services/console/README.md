# SATUSEHAT Integration Console

Language-neutral dashboard, durable client webhook, and correction API for the SQLite queue shared by all SDK implementations.

```bash
export SATUSEHAT_QUEUE_PATH=./satusehat-sdk.db
python3 services/console/server.py
# open http://127.0.0.1:8787
```

Webhook:

```bash
export SATUSEHAT_WEBHOOK_URL=https://simrs.example.id/integration/satusehat/events
export SATUSEHAT_WEBHOOK_SECRET='replace-with-secret'
export SATUSEHAT_WEBHOOK_EVENTS=correction_required,dead_letter
python3 services/console/server.py
```

For HTTP 400/422 failures, a durable `integration.correction_required` message is delivered. The message contains event/correlation/error metadata, not the full FHIR payload.

Attach source context (optional):

```bash
curl -X POST http://127.0.0.1:8787/api/v1/events/<event-id>/context \
  -H 'Content-Type: application/json' \
  -d '{"correlation_id":"visit-123","source_system":"SIMRS-ABC","source_record_id":"ENC-92882"}'
```

Submit corrected data:

```bash
curl -X POST http://127.0.0.1:8787/api/v1/events/<event-id>/corrections \
  -H 'Content-Type: application/json' \
  -d '{"payload":{"resourceType":"Encounter","status":"finished"}}'
```

A new `QUEUED` revision is created. The old failed event remains available for audit and points to the new event through `superseded_by_event_id`.

If exposed beyond localhost set `SATUSEHAT_CONSOLE_API_TOKEN` and use `Authorization: Bearer <token>` on POST endpoints.

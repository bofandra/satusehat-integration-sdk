# Monitoring, Webhook, and Correction Workflow

v0.2 adds one language-neutral Integration Console on top of the SQLite queue shared by Python, Node.js, Go, Java, PHP, and .NET.

```text
SIMRS -> SDK queue -> SDK worker -> SATUSEHAT
                              | HTTP 400/422
                              v
                   WAITING_FOR_CORRECTION
                              |
                              v
                   Integration Console
                    | dashboard  | webhook
                    |            v
                    |          SIMRS
                    |            | corrected source data
                    |            v
                    +---- POST /api/v1/events/{id}/corrections
                                 |
                                 v
                       NEW REVISION / QUEUED
```

Run:

```bash
SATUSEHAT_QUEUE_PATH=./satusehat-sdk.db python3 services/console/server.py
```

Open `http://127.0.0.1:8787`.

Configure webhook:

```bash
SATUSEHAT_WEBHOOK_URL=https://simrs.example.id/integration/satusehat/events
SATUSEHAT_WEBHOOK_SECRET=replace-me
SATUSEHAT_WEBHOOK_EVENTS=correction_required,dead_letter
```

HTTP `400`/`422` becomes `CORRECT_DATA`; `404` becomes `REVIEW_REFERENCE`. The webhook excludes the full FHIR payload and carries event ID, idempotency key, optional source context, HTTP status, and parsed OperationOutcome issues.

If a secret is set, callbacks include `X-SSSDK-Event`, `X-SSSDK-Delivery`, `X-SSSDK-Timestamp`, and `X-SSSDK-Signature`. Signature input is `timestamp + "." + raw_body` with HMAC-SHA256.

Client systems can attach source metadata through `POST /api/v1/events/{event_id}/context`, then submit corrected FHIR through `POST /api/v1/events/{event_id}/corrections`. A correction creates a new `QUEUED` event with a higher revision. The failed event remains as audit evidence and receives `superseded_by_event_id`.

The server binds to `127.0.0.1` by default. Set `SATUSEHAT_CONSOLE_API_TOKEN` before exposing POST endpoints beyond localhost; terminate TLS at the facility reverse proxy/API gateway.

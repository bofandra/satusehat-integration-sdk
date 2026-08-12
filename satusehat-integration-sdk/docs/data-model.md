# Data Model

## integration_events

`event_id` is a locally generated immutable ID used for audit and deduplication.

`organization_id` identifies the SATUSEHAT organization credential scope.

`operation` is one of `POST`, `PUT`, `PATCH`, `GET`. Queue workflows normally use POST/PUT/PATCH.

`resource_type` is the FHIR resource name, e.g. `Encounter`, `Condition`.

`resource_id` is required for PUT/PATCH and optional for POST.

`payload_json` stores raw FHIR JSON. It may contain sensitive clinical data.

`status` follows the common lifecycle.

`attempt` counts processing attempts, not enqueue calls.

`next_retry_at` allows the worker to skip events until a scheduled retry window.

## Lifecycle

```text
QUEUED -> PROCESSING -> SUCCESS
                    -> WAITING_FOR_CORRECTION
                    -> RATE_LIMITED -> PROCESSING
                    -> RETRYING -> PROCESSING
                    -> DEAD_LETTER
```

A corrected clinical record should preferably generate a new integration event. If replaying an old event, ensure the stored payload itself has been updated intentionally.

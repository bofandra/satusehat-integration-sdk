# Retry Policy

## Classification

| Condition | Category | Retry |
|---|---|---|
| 2xx | success | No |
| 400 | invalid_request | No automatic retry |
| 401 | unauthorized | Token invalidate then retry |
| 403 | forbidden | No automatic retry |
| 404 | not_found | No automatic retry by default |
| 409 | conflict | No automatic retry by default |
| 422 | validation_error | No automatic retry |
| 429 | rate_limited | Yes |
| 5xx | server_error | Yes |
| network/timeout | transport_error | Yes |

## Backoff

```text
min(max_backoff, initial_backoff * 2^(attempt-1)) + random jitter
```

If a valid `Retry-After` header is present on 429, prefer that delay.

## Dead Letter

When the attempt count reaches `max_retries`, the event becomes `DEAD_LETTER`. Do not blindly replay dead letters: fix credential/data/network/root-cause first.

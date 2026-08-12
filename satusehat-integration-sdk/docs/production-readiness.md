# Production Readiness Checklist

The repository is ready to publish as a **reference SDK repository**, but an organization adopting it for production should complete the following review.

## Governance

- Confirm the official GitHub organization/repository name.
- Confirm ownership of Maven, npm, Packagist, PyPI, NuGet, and Go module namespaces.
- Confirm copyright holder and NOTICE wording.
- Assign maintainers and security response contacts.
- Define supported SDK versions and end-of-support policy.

## SATUSEHAT compatibility

- Re-run sandbox integration tests against the current official SATUSEHAT endpoints.
- Test representative positive and negative OperationOutcome responses.
- Verify PATCH media type/format for the intended endpoint/use case.
- Verify rate limit configuration for each organization.
- Verify resource/playbook requirements against current SATUSEHAT documentation.

## Infrastructure

- Put the SQLite queue on durable encrypted storage.
- Monitor disk space, queue depth, oldest event age, dead-letter count, and error distribution.
- Run worker separately from latency-sensitive clinical web/API threads where possible.
- Use one active worker per default SQLite queue file; use a shared queue adapter for concurrent workers.
- Use a transactional outbox if local DB commit and SDK enqueue must be lossless together.
- For multi-instance/high-availability deployments, use a shared queue adapter rather than independent SQLite queues.

## Security & privacy

- Store production secrets in a secret manager or protected runtime environment.
- Never log access tokens/client secrets.
- Ensure queue backups are treated as clinical data if payloads contain PHI/PII.
- Define retention and deletion policies.
- Run dependency and SAST scans in CI.

## Testing

- Unit tests.
- Mock end-to-end tests.
- SATUSEHAT sandbox contract tests.
- Network timeout/reconnect tests.
- 401/403/422/429/5xx tests.
- Restart/recovery test with events pending in SQLite.
- Load test at the expected fasyankes peak throughput.

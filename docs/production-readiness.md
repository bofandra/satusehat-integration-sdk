# Production Readiness Status

The repository is ready to publish as an **reference SDK v0.2.0** after the required release evidence below is attached to the GitHub release.

This is a production release of the reference SDK project. It is not a Ministry/Kementerian Kesehatan official SDK unless a separate governance decision transfers ownership and branding authority.

## Required release evidence

| Gate | Required evidence before `v0.2.0` publish |
|---|---|
| Governance | Repository owner, maintainer team, security reporting route, license/NOTICE owner, and public package namespace ownership are confirmed. |
| CI | GitHub Actions `ci` passes for Python, Go, Node.js 20/22/24, Java 21, PHP 8.3, and .NET 8. |
| Sandbox contract | Manual `sandbox-contract` workflow passes with official SATUSEHAT sandbox credentials and no production endpoints. |
| Live write matrix | `tools/sandbox_write_matrix.sh` creates one non-PHI sandbox `Organization` through every SDK, or release owner records an approved exception. |
| Clinical write matrix | `tools/sandbox_clinical_matrix.sh` creates approved sandbox `Location`, `Encounter`, `Condition`, and `Observation` resources through every SDK, or release owner records an approved exception. |
| Lab panel write matrix | `tools/sandbox_lab_matrix.sh` creates approved sandbox `ServiceRequest`, `Specimen`, three lab `Observation` resources, and `DiagnosticReport` through every SDK, or release owner records an approved exception. |
| Security | Manual/automatic `security` workflow passes, or exceptions are recorded with owner/date. |
| Packaging | Dry-run package builds pass for every SDK ecosystem. |
| Release artifacts | GitHub release contains release notes, artifacts where applicable, SBOM/checksum evidence, and rollback notes. |

## Governance

- GitHub repository: `github.com/bofandra/satusehat-integration-sdk`.
- Default maintainer team: `@bofandra`.
- Copyright holder: `SATUSEHAT Integration SDK Contributors`.
- Supported production reference line: `0.1.x`.
- Patch releases are for bug fixes, security fixes, packaging fixes, and documentation corrections.
- Breaking public API changes require a minor version bump before `1.0.0`, and a major version bump after `1.0.0`.
- If a registry namespace is unavailable, stop the release and rename consistently across docs/manifests before publishing.

## SATUSEHAT compatibility

- Re-run sandbox integration tests against the current official SATUSEHAT endpoints before each official release.
- Test representative positive and negative OperationOutcome responses.
- Verify PATCH media type/format for the intended endpoint/use case. The SDK defaults PATCH to `Content-Type: application/json`, matching current SATUSEHAT documentation examples.
- Verify rate limit configuration for each organization.
- Verify resource/playbook requirements against current SATUSEHAT documentation.
- Do not run automated release gates against production SATUSEHAT endpoints.

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
- Keep GitHub secret scanning and private vulnerability reporting enabled on the release repository.

## Testing

- Unit tests.
- Mock end-to-end tests.
- SATUSEHAT sandbox contract tests.
- SATUSEHAT live write matrix tests with non-PHI fixtures.
- SATUSEHAT clinical write matrix tests with approved sandbox Patient/Practitioner fixtures.
- SATUSEHAT lab panel write matrix tests with approved sandbox Patient/Practitioner fixtures.
- Network timeout/reconnect tests.
- 401/403/422/429/5xx tests.
- Restart/recovery test with events pending in SQLite, including stale `PROCESSING` lease recovery.
- Load test at the expected fasyankes peak throughput.

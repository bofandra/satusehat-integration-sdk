# Security Policy

## Reporting

Do not open a public issue containing API credentials, patient data, security tokens, or exploitable vulnerability details.

For the official reference release repository, report vulnerabilities through GitHub private vulnerability reporting for `github.com/bofandra/satusehat-integration-sdk`. If private reporting is not enabled, contact the repository owner through the public maintainer channel and share only non-sensitive coordination details until a private channel is established.

## Supported Versions

| Version | Supported |
|---|---|
| `0.1.x` | Yes |
| `<0.1.0` | No |

## Credential Handling

- Never commit `client_id`/`client_secret`.
- Load production credentials from environment or a secret manager.
- Do not print access tokens in logs.
- Invalidate token cache after HTTP 401.

## Clinical Data

The SQLite queue may contain FHIR payloads. Treat the database as sensitive clinical data:

- use encrypted disks/volumes;
- restrict filesystem permissions;
- configure backup retention appropriately;
- avoid copying queue DB to development machines;
- do not ship queue payloads to external observability services.

## Dependency Security

Run the package ecosystem security tools (Dependabot/Renovate, `npm audit`, Maven dependency scanning, Composer audit, NuGet audit, etc.) as part of repository governance.

# Release Process

This repository publishes an official production-ready reference SDK for SATUSEHAT integrations. It is not an official Ministry/Kementerian Kesehatan SDK unless that authority is separately granted.

## Release gates

Before tagging `v0.2.0`, the maintainer must record evidence in `VALIDATION.md` for:

- `ci` workflow pass;
- `security` workflow pass or approved exceptions;
- `sandbox-contract` workflow pass with official SATUSEHAT sandbox credentials;
- `tools/sandbox_write_matrix.sh` pass, or an approved decision to skip live write testing for that release;
- `tools/sandbox_clinical_matrix.sh` pass with approved sandbox Patient/Practitioner fixtures, or an approved decision to skip patient-linked sandbox testing;
- registry ownership confirmation for npm, PyPI, Maven, Packagist, NuGet, and Go;
- `release` workflow dry run with `publish=false`.

## Required GitHub secrets

- `SATUSEHAT_SANDBOX_CLIENT_ID`
- `SATUSEHAT_SANDBOX_CLIENT_SECRET`
- `SATUSEHAT_SANDBOX_ORGANIZATION_ID`
- `NPM_TOKEN`
- `PYPI_API_TOKEN`
- `NUGET_API_KEY`
- `PACKAGIST_USERNAME`
- `PACKAGIST_API_TOKEN`
- `MAVEN_DEPLOY_REPOSITORY`
- `MAVEN_USERNAME`
- `MAVEN_PASSWORD`
- `MAVEN_GPG_PRIVATE_KEY`
- `MAVEN_GPG_PASSPHRASE`

Maven Central publication additionally requires the repository owner's selected Central Portal or OSSRH credentials and signing keys.

## Tagging

```bash
git tag -a v0.2.0 -m "SATUSEHAT Integration SDK v0.2.0"
git push origin v0.2.0
git tag -a sdks/go/v0.2.0 -m "SATUSEHAT Integration SDK Go v0.2.0"
git push origin sdks/go/v0.2.0
```

## Publishing

Run the manual `release` workflow from tag `v0.2.0` with `publish=false`. After artifacts and checksums are verified, rerun from the same tag with `publish=true`.

Go module discovery publishes from the public Git tags. Packagist is refreshed through its update-package API. Maven publication uses `MAVEN_DEPLOY_REPOSITORY` so the repository owner can choose Central Portal/OSSRH without hard-coding a vendor endpoint in source.

## Rollback

- Prefer publishing a patch release over deleting immutable public versions.
- Deprecate npm versions that should no longer be used.
- Yank PyPI versions only when appropriate.
- Deprecate NuGet packages when a release is superseded.
- For Maven, publish a fixed patch version and mark the bad version in release notes.
- Delete a Git tag only if it exposes secrets or legally sensitive material.

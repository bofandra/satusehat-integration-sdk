# Publishing to GitHub and Package Registries

## 1. Confirm release authority

This repository publishes an **official production-ready reference SDK**, not an official Ministry/Kementerian Kesehatan SDK unless that ownership is separately approved.

Before publication, confirm:

- repository organization and URL: `github.com/bofandra/satusehat-integration-sdk`;
- package registry namespaces listed in `README.md`;
- copyright/NOTICE owner;
- maintainer/security contact;
- official reference SDK branding and repository description.

## 2. Repository settings

Required:

- protect `main`;
- require pull request review;
- require the `ci`, `security`, and `sandbox-contract` gates for release branches/tags;
- enable Dependabot alerts/security updates;
- enable secret scanning;
- enable private vulnerability reporting;
- configure `.github/CODEOWNERS` with the active maintainer team.

## 3. Required secrets

Configure these repository or environment secrets before running release workflows:

- `SATUSEHAT_SANDBOX_CLIENT_ID`
- `SATUSEHAT_SANDBOX_CLIENT_SECRET`
- `SATUSEHAT_SANDBOX_ORGANIZATION_ID`
- `NPM_TOKEN`
- `PYPI_API_TOKEN`
- `RUBYGEMS_API_KEY`
- `NUGET_API_KEY`
- `PACKAGIST_USERNAME`
- `PACKAGIST_API_TOKEN`
- `MAVEN_DEPLOY_REPOSITORY`
- `MAVEN_USERNAME`
- `MAVEN_PASSWORD`
- `MAVEN_GPG_PRIVATE_KEY`
- `MAVEN_GPG_PASSPHRASE`

Do not store SATUSEHAT production credentials in release workflow secrets.

## 4. Release gates

Run and archive evidence for:

```bash
gh workflow run ci.yml
gh workflow run security.yml
gh workflow run sandbox-contract.yml
```

The sandbox workflow must pass using official sandbox credentials and must not use production endpoints.

## 5. Tagging

After all gates pass and `VALIDATION.md` contains the evidence:

```bash
git tag -a v0.2.0 -m "SATUSEHAT Integration SDK v0.2.0"
git push origin v0.2.0
```

The Go SDK lives in a subdirectory module, so also push:

```bash
git tag -a sdks/go/v0.2.0 -m "SATUSEHAT Integration SDK Go v0.2.0"
git push origin sdks/go/v0.2.0
```

## 6. Publish

Run the manual `release` workflow from the `v0.2.0` tag. Keep `publish=false` for the final dry run, then rerun with `publish=true` only after registry ownership is confirmed.

Manual registry commands, if needed:

```bash
cd sdks/node && npm publish --access public
cd sdks/python && python -m build && twine upload dist/*
cd sdks/ruby && gem build satusehat-integration-sdk.gemspec && gem push satusehat-integration-sdk-*.gem
cd sdks/dotnet && dotnet pack -c Release && dotnet nuget push bin/Release/*.nupkg --source https://api.nuget.org/v3/index.json
```

Go publishes from the public Git tag. Packagist is refreshed through its update-package API. Maven publication uses the repository owner's `MAVEN_DEPLOY_REPOSITORY` secret so Central Portal/OSSRH endpoint choices are not hard-coded in source.

## 7. Rollback

- GitHub: mark the release as deprecated or delete the release asset if it contains a packaging error.
- npm: deprecate the version; unpublish only if registry policy allows and the package is unsafe.
- PyPI/RubyGems/NuGet/Maven: yank/deprecate where supported; otherwise publish a fixed patch version.
- Packagist/Go: leave the immutable tag in place unless it exposes secrets; publish a patch tag and document the superseded version.

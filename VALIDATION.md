# Validation Evidence — v0.1.0

Tanggal pemeriksaan: 2026-08-12.

Status release: **official production-ready reference SDK**. Evidence eksternal masih harus dilengkapi oleh maintainer release sebelum tag dan package publik dibuat.

## Required release gates

| Gate | Status | Evidence |
|---|---|---|
| CI multi-language | Pending remote run | GitHub Actions `ci` URL harus ditambahkan sebelum publish. |
| SATUSEHAT sandbox contract | Passed locally; pending remote run | `tools/sandbox_contract.py` passed with official sandbox credentials on 2026-08-12. GitHub Actions `sandbox-contract` URL harus ditambahkan sebelum publish. |
| SATUSEHAT live write matrix | Passed locally; pending remote policy decision | `tools/sandbox_write_matrix.sh` created one non-PHI sandbox `Organization` via each SDK on 2026-08-12. |
| SATUSEHAT clinical write matrix | Passed locally; pending remote policy decision | `tools/sandbox_clinical_matrix.sh` created patient-linked sandbox `Location`, `Encounter`, `Condition`, and `Observation` via each SDK on 2026-08-12 after explicit user approval. |
| SATUSEHAT lab panel write matrix | Passed locally; pending remote policy decision | `tools/sandbox_lab_matrix.sh` created patient-linked sandbox `Location`, `Encounter`, `ServiceRequest`, `Specimen`, three lab `Observation` resources, and `DiagnosticReport` via each SDK on 2026-08-22 after explicit user approval. |
| Security scan | Pending remote run | GitHub Actions `security` URL atau exception record harus ditambahkan sebelum publish. |
| Registry namespace ownership | Pending external confirmation | npm, PyPI, Maven, Packagist, NuGet, and Go module ownership must be confirmed. |
| Package dry run | Pending release workflow | GitHub Actions `release` dry-run URL harus ditambahkan sebelum publish. |

Do not publish v0.1.0 packages until every gate above is either passed or has a documented, approved exception.

## Pemeriksaan otomatis

GitHub Actions:

- `.github/workflows/ci.yml` menjalankan build/test pada environment bersih untuk Python, Go, Node.js, Java, PHP, dan .NET.
- `.github/workflows/sandbox-contract.yml` menjalankan kontrak sandbox read-only default dengan credential resmi SATUSEHAT sandbox.
- `.github/workflows/security.yml` menjalankan dependency/security checks lintas ekosistem.
- `.github/workflows/release.yml` membuat package artifacts dan dapat mempublikasikan setelah guard manual terpenuhi.

## Pemeriksaan lokal pada 2026-08-12

- Python: `pytest` lulus 9 test; package wheel berhasil dibangun dan di-install.
- Python packaging: `python -m build --no-isolation` berhasil membuat wheel/sdist; `twine check dist/*` lulus.
- Node.js: `npm test`, `npm run build`, dan `npm pack --dry-run` lulus dengan Node 24.14.0. Node 23 lokal tidak termasuk support matrix.
- Java: `mvn test` lulus 6 test; `mvn -Prelease -Dgpg.skip=true package` berhasil membuat jar, sources jar, dan javadocs jar.
- Go: `go test ./...` lulus dengan Go 1.23.0 toolchain dan cache lokal `/private/tmp`.
- .NET: `dotnet build --no-restore` lulus tanpa warning; `dotnet pack` berhasil membuat `.nupkg`.
- Sandbox contract gate: `tools/sandbox_contract.py` lulus terhadap SATUSEHAT sandbox resmi dengan credential sandbox resmi. Checks: OAuth client credentials passed, FHIR metadata read returned HTTP 200, optional write skipped.
- Live sandbox write matrix: `tools/sandbox_write_matrix.sh` lulus terhadap SATUSEHAT sandbox resmi dengan satu non-PHI `Organization` per SDK:
  - Python: HTTP 201, resource `Organization/8dc77b70-de5f-4a09-a50f-9984b6b26133`.
  - Node.js: HTTP 201, resource `Organization/80f3d1cc-2338-429b-83e6-fe56789335a6`.
  - Go: HTTP 201, resource `Organization/21009c1c-1034-4144-bf1a-ae2905af91b9`.
  - Java: HTTP 201, resource `Organization/a753fa2d-6fac-4a52-8358-7a2a48c7a145`.
  - PHP: HTTP 201, resource `Organization/1170d623-48c0-4947-92af-9783c1c821e2`.
  - .NET: HTTP 201, resource `Organization/f938ab2a-e3b1-46f0-991f-9a3214e2ac8a`.
- Clinical sandbox write matrix: `tools/sandbox_clinical_matrix.sh` lulus terhadap SATUSEHAT sandbox resmi dengan `Location`, `Encounter`, `Condition`, dan `Observation` per SDK menggunakan Patient/Practitioner sandbox yang disetujui user:
  - Python: `Location/2cc35325-c945-43f1-bba7-e2239458a070`, `Encounter/5ee3dd00-7916-46ce-80b8-530f31d8e79f`, `Condition/9140a3da-b008-42b1-9b15-1152c8578290`, `Observation/f84fc041-f782-46ce-9d09-0d1d5518cb79`.
  - Node.js: `Location/efd9a273-fa0e-4709-9fb4-76ce2ad1a688`, `Encounter/b15127aa-bed4-43fd-aa64-833c1ae6dc73`, `Condition/79c192bd-3c12-4282-8fbb-8dc230e31270`, `Observation/64dce449-1cc8-4115-9b59-40ee47b7d191`.
  - Go: `Location/dbf317ef-0705-44f0-9a2c-9557384f5ff9`, `Encounter/7539967f-8b4f-4706-800a-24ffc5d1b6e4`, `Condition/c5fa2f08-1dbb-481e-994a-06f39d8a3462`, `Observation/0b31b83c-5c2d-4df9-9cb1-c1825cd4a1d6`.
  - Java: `Location/dbb5ad84-e73d-4696-ba43-57f9d4047d89`, `Encounter/d4a5272d-b8cb-4684-8621-104611c635b3`, `Condition/8ab093d4-3a6a-4933-9589-4806be4f1818`, `Observation/a921accc-4251-4dc8-9e92-d26b113f94d2`.
  - PHP: `Location/12af8bca-b0b3-4fb5-afe5-6b2c53783a11`, `Encounter/c5a58849-dce5-4c2f-b0bc-b81d0df9209a`, `Condition/58a7b5b8-d19d-45cf-8797-a7b1ae80f3cf`, `Observation/deb5083b-e433-41ad-a029-f59c02a509fa`.
  - .NET: `Location/625ea2f7-a661-4f7c-bf4c-3e4fc33caf5a`, `Encounter/dd51a36e-aa73-4ee7-8f88-e35df2f24ec6`, `Condition/b06a6c26-7b59-4293-acc7-0d28e888afc5`, `Observation/4b588d97-7eeb-43f6-b51e-45d6ac9895b8`.
- Lab panel sandbox write matrix: `tools/sandbox_lab_matrix.sh` lulus terhadap SATUSEHAT sandbox resmi dengan `Location`, `Encounter`, `ServiceRequest`, `Specimen`, tiga `Observation`, dan `DiagnosticReport` per SDK menggunakan Patient/Practitioner sandbox yang disetujui user:
  - Python: `Location/7cc47ac9-3b94-4b9d-8fa1-1f0e1907cddf`, `Encounter/501ce439-19fb-46a7-93b2-8dc8eeba4ab6`, `ServiceRequest/459a41d0-e10d-44ec-b9f4-1d5cc72d9c0c`, `Specimen/f63b0f5a-98ef-4afe-aad9-a3597ae04521`, `Observation/0ea48b7c-76ac-4edb-82c6-7deca87f3300`, `Observation/1b98ef66-e4b1-4f80-ba4c-06c0b25a3e93`, `Observation/ccf85a65-98b2-451e-b01b-1ea1acbc18d8`, `DiagnosticReport/5c525be5-8e81-4f93-8c64-9a0d2b9ff7cb`.
  - Node.js: `Location/8b4285fa-bb69-4881-a34c-d40f5d880cd6`, `Encounter/d69d10f3-6400-4a4c-92a2-56b937e1e3e7`, `ServiceRequest/12c82bc5-6a49-47b6-b23b-986626f75da1`, `Specimen/41654ae6-4cf0-4d09-a2ff-801288bf6665`, `Observation/916ccd28-6361-44ad-b39d-def351c65ca6`, `Observation/2c640d96-7888-466b-96e6-7693dfc19e41`, `Observation/de7e061d-06ab-4e86-ade7-6b94461b592e`, `DiagnosticReport/5e069332-c9bb-4b89-a56f-819e78e2074a`.
  - Go: `Location/4538cacc-854c-47c8-ae72-41ffa2fa3f92`, `Encounter/02c38b51-8dbe-4502-a7eb-98f471e46218`, `ServiceRequest/6f80cfd1-38a7-41ff-82fb-f8670e229665`, `Specimen/04ac22db-4efa-4bcb-8c25-a98f13d2ac82`, `Observation/189d4837-aebf-457c-af27-fbb559c94bab`, `Observation/2eec9cab-a384-445d-9ae1-228f02a79cbb`, `Observation/1934444a-b480-4a1e-847a-11ffd9085c47`, `DiagnosticReport/714ff441-ff8c-42ac-8cd5-1a5c7229a568`.
  - Java: `Location/a2ff92b6-7874-49dc-ac4c-e2d4dabc20f7`, `Encounter/7ab3d6d2-bc26-4639-974f-61e9fcf282c6`, `ServiceRequest/3160beb1-073c-43a7-a9a6-2e8aaad1f99c`, `Specimen/f80acac7-bc99-49e1-acec-4220725d7547`, `Observation/d8daf83b-d41d-4d18-9567-c12bb8fd4271`, `Observation/704a7174-87ec-494f-9923-c1f2eb2cb8a8`, `Observation/ad958d11-02fc-4c37-9597-b24ad5257bee`, `DiagnosticReport/a5c5e022-5b0e-4490-a516-9f1272a2cd97`.
  - PHP: `Location/61a0966e-2341-4546-b021-d8da7e08d46e`, `Encounter/37c3bf6b-9d64-43d4-b571-a2f355eef6d4`, `ServiceRequest/4929bda9-4d9c-408a-8d39-f69ecfbcbf22`, `Specimen/870c7f43-4131-4f44-9c6f-e7cba3cd2466`, `Observation/54c5fc25-8db9-4a37-91b4-20f4d024e819`, `Observation/314a95fb-8167-423a-b665-39ff63b25939`, `Observation/45705556-ce4b-4095-809a-b12f716dacfc`, `DiagnosticReport/136409fc-2c16-4153-8ce1-e55e976760b4`.
  - .NET: `Location/df05f4cc-76b4-4f69-978b-f1c838bfcc7f`, `Encounter/83f8ffe4-e45b-4477-bbc4-d9e620ddc10a`, `ServiceRequest/a5bed329-acb7-4776-8505-b88b541271fe`, `Specimen/4f14ccb5-7c5d-4de3-9fca-608d8ac03b03`, `Observation/94784c8f-3ef9-4111-af9b-f3842e4b6a00`, `Observation/d23691ce-7313-4df7-8d4c-5b102fe04cab`, `Observation/67f496d0-320b-4967-af2b-c2d3958c3062`, `DiagnosticReport/f498aad3-4197-4b70-b3d0-2ca684a860ec`.
- Repository metadata: JSON schema, Maven POM XML, GitHub YAML, dan Dependabot YAML berhasil diparse.
- PHP: `composer validate --strict` lulus. Live sandbox write dijalankan dengan PHP 8.4.8 karena default `php` mesin ini masih PHP 7.4.

## SATUSEHAT reference verification

Official SATUSEHAT documentation checked on 2026-08-12:

- Endpoint Information confirms sandbox OAuth/FHIR and production OAuth/FHIR base URLs.
- Access Token documentation confirms `POST /accesstoken?grant_type=client_credentials` with `application/x-www-form-urlencoded`.
- SATUSEHAT documentation portal reports version 7.23.

## Catatan

Status repository adalah rilis produksi untuk **reference implementation**. Repo ini bukan rilis resmi Kementerian Kesehatan sampai ditetapkan melalui governance/release resmi Kementerian Kesehatan.

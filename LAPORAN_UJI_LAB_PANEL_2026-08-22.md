# Laporan Uji Lab Panel SATUSEHAT Sandbox

Tanggal: 2026-08-22  
Environment: SATUSEHAT staging/sandbox  
Use case: `ServiceRequest -> Specimen -> Observation -> DiagnosticReport` untuk panel elektrolit

## Ringkasan

Hari ini dilakukan implementasi dan validasi live untuk use case lab panel SATUSEHAT. SDK tetap dipertahankan sebagai generic FHIR client, sehingga tidak ada perubahan public API. Validasi dilakukan dengan membuat chain resource FHIR lab panel melalui enam SDK: Python, Node.js, Go, Java, PHP, dan .NET.

Hasil akhir: semua SDK berhasil membuat seluruh chain lab panel di SATUSEHAT sandbox dengan HTTP `201`.

## Perubahan Repo

File baru:

- `tools/sandbox_lab_matrix.sh`
  - Script live sandbox matrix untuk `python node go java php dotnet`.
  - Membuat `Location`, `Encounter`, `ServiceRequest`, `Specimen`, tiga `Observation`, dan `DiagnosticReport`.
  - Mencetak output JSON redaction-safe per resource: resource type, HTTP status, returned resourceType, dan ID.

File yang diperbarui:

- `Makefile`
  - Menambahkan target `sandbox-lab`.
- `PANDUAN_UJI_SATUSEHAT_SANDBOX.md`
  - Menambahkan dokumentasi lab panel POST matrix.
  - Menambahkan resource `ServiceRequest`, `Specimen`, dan `DiagnosticReport` sebagai resource yang sudah diuji.
- `docs/production-readiness.md`
  - Menambahkan lab panel write matrix sebagai release evidence gate.
- `VALIDATION.md`
  - Mengubah status lab panel write matrix menjadi passed locally.
  - Menambahkan daftar resource IDs hasil uji live sandbox.

## Payload Lab Panel

Resource yang dibuat per SDK:

1. `Location`
2. `Encounter`
3. `ServiceRequest`
4. `Specimen`
5. `Observation` natrium
6. `Observation` kalium
7. `Observation` klorida
8. `DiagnosticReport`

Kode klinis yang digunakan:

| Resource | Kode | Sistem | Keterangan |
|---|---|---|---|
| `ServiceRequest.code` | `24326-1` | `http://loinc.org` | Electrolyte panel |
| `ServiceRequest.category` | `108252007` | `http://snomed.info/sct` | Laboratory procedure |
| `Specimen.type` | `119364003` | `http://snomed.info/sct` | Serum specimen |
| `Observation` natrium | `2951-2` | `http://loinc.org` | Sodium |
| `Observation` kalium | `2823-3` | `http://loinc.org` | Potassium |
| `Observation` klorida | `2075-0` | `http://loinc.org` | Chloride |
| `DiagnosticReport.code` | `24326-1` | `http://loinc.org` | Electrolyte panel |

## Validasi yang Dilakukan

Validasi read-only:

- OAuth client credentials ke SATUSEHAT staging: passed.
- FHIR metadata read: HTTP `200`.
- Optional write pada contract tool: skipped.

Validasi local implementation:

- `bash -n tools/sandbox_lab_matrix.sh`: passed.
- `make -n sandbox-lab`: passed.
- Extracted heredoc syntax/compile check untuk Python, Node.js, PHP, Go, Java, dan .NET: passed.
- `go test ./...`: passed.
- Java `mvn test`: passed.
- `.NET dotnet build`: passed.
- Node `npm run build`: passed.

Catatan local runtime:

- Python unit test via `pytest` belum dijalankan karena package `pytest` belum tersedia di environment lokal.
- PHP default machine adalah `7.4.33`, sedangkan SDK membutuhkan PHP `8.2+`; uji live PHP dijalankan dengan PHP `8.4.8`.
- Node default machine adalah `23.5.0` dan menyebabkan segmentation fault pada SDK Node; uji live Node berhasil setelah memakai Node `22.23.2`.

## Hasil Live SATUSEHAT Sandbox

Semua resource di bawah dibuat di SATUSEHAT staging/sandbox. Credential tidak ditulis ke file repo.

| SDK | Location | Encounter | ServiceRequest | Specimen | Observation Sodium | Observation Potassium | Observation Chloride | DiagnosticReport |
|---|---|---|---|---|---|---|---|---|
| Python | `7cc47ac9-3b94-4b9d-8fa1-1f0e1907cddf` | `501ce439-19fb-46a7-93b2-8dc8eeba4ab6` | `459a41d0-e10d-44ec-b9f4-1d5cc72d9c0c` | `f63b0f5a-98ef-4afe-aad9-a3597ae04521` | `0ea48b7c-76ac-4edb-82c6-7deca87f3300` | `1b98ef66-e4b1-4f80-ba4c-06c0b25a3e93` | `ccf85a65-98b2-451e-b01b-1ea1acbc18d8` | `5c525be5-8e81-4f93-8c64-9a0d2b9ff7cb` |
| Node.js | `8b4285fa-bb69-4881-a34c-d40f5d880cd6` | `d69d10f3-6400-4a4c-92a2-56b937e1e3e7` | `12c82bc5-6a49-47b6-b23b-986626f75da1` | `41654ae6-4cf0-4d09-a2ff-801288bf6665` | `916ccd28-6361-44ad-b39d-def351c65ca6` | `2c640d96-7888-466b-96e6-7693dfc19e41` | `de7e061d-06ab-4e86-ade7-6b94461b592e` | `5e069332-c9bb-4b89-a56f-819e78e2074a` |
| Go | `4538cacc-854c-47c8-ae72-41ffa2fa3f92` | `02c38b51-8dbe-4502-a7eb-98f471e46218` | `6f80cfd1-38a7-41ff-82fb-f8670e229665` | `04ac22db-4efa-4bcb-8c25-a98f13d2ac82` | `189d4837-aebf-457c-af27-fbb559c94bab` | `2eec9cab-a384-445d-9ae1-228f02a79cbb` | `1934444a-b480-4a1e-847a-11ffd9085c47` | `714ff441-ff8c-42ac-8cd5-1a5c7229a568` |
| Java | `a2ff92b6-7874-49dc-ac4c-e2d4dabc20f7` | `7ab3d6d2-bc26-4639-974f-61e9fcf282c6` | `3160beb1-073c-43a7-a9a6-2e8aaad1f99c` | `f80acac7-bc99-49e1-acec-4220725d7547` | `d8daf83b-d41d-4d18-9567-c12bb8fd4271` | `704a7174-87ec-494f-9923-c1f2eb2cb8a8` | `ad958d11-02fc-4c37-9597-b24ad5257bee` | `a5c5e022-5b0e-4490-a516-9f1272a2cd97` |
| PHP | `61a0966e-2341-4546-b021-d8da7e08d46e` | `37c3bf6b-9d64-43d4-b571-a2f355eef6d4` | `4929bda9-4d9c-408a-8d39-f69ecfbcbf22` | `870c7f43-4131-4f44-9c6f-e7cba3cd2466` | `54c5fc25-8db9-4a37-91b4-20f4d024e819` | `314a95fb-8167-423a-b665-39ff63b25939` | `45705556-ce4b-4095-809a-b12f716dacfc` | `136409fc-2c16-4153-8ce1-e55e976760b4` |
| .NET | `df05f4cc-76b4-4f69-978b-f1c838bfcc7f` | `83f8ffe4-e45b-4477-bbc4-d9e620ddc10a` | `a5bed329-acb7-4776-8505-b88b541271fe` | `4f14ccb5-7c5d-4de3-9fca-608d8ac03b03` | `94784c8f-3ef9-4111-af9b-f3842e4b6a00` | `d23691ce-7313-4df7-8d4c-5b102fe04cab` | `67f496d0-320b-4967-af2b-c2d3958c3062` | `f498aad3-4197-4b70-b3d0-2ca684a860ec` |

## Status Akhir

- Lab panel write matrix: passed locally against SATUSEHAT staging/sandbox.
- Semua SDK berhasil membuat chain resource lab lengkap.
- Evidence sudah dicatat di `VALIDATION.md`.
- Credential yang digunakan untuk uji tidak ditulis ke repo.
- Karena client secret sempat dikirim melalui chat, disarankan untuk rotasi secret setelah validasi selesai.


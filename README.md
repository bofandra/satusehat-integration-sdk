# SATUSEHAT Integration SDK

Reference implementation open-source untuk membantu SIMRS, SIMPUS, HIS, EMR, LIS, RIS, dan aplikasi fasyankes terhubung ke API FHIR SATUSEHAT dengan pola yang konsisten, aman, dapat di-retry, dan dapat dimonitor.

> **Status:** reference implementation v0.2.0. Repo ini bersifat open-source/community reference dan bukan rilis resmi Kementerian Kesehatan sampai ditetapkan melalui proses governance/release resmi.

## Tujuan

SDK ini mengurangi pekerjaan berulang di setiap vendor dengan menyediakan komponen standar untuk:

- OAuth2 `client_credentials` dan cache token.
- FHIR REST core: `GET`, `POST`, `PUT`, dan JSON `PATCH`.
- Persistent local queue berbasis SQLite.
- Worker untuk pengiriman asinkron.
- Retry untuk network error, HTTP `429`, dan `5xx`.
- Exponential backoff + jitter.
- Rate limiting lokal per organisasi.
- Klasifikasi error yang konsisten.
- Status lifecycle pengiriman.
- Event ID unik untuk audit dan pelacakan transaksi integrasi.
- Idempotency key opsional untuk mencegah duplicate enqueue dari retry publisher.
- Audit metadata tanpa wajib menyimpan telemetry klinis eksternal.
- Kontrak SDK yang seragam di beberapa bahasa.
- Optional **Integration Console** untuk dashboard monitoring lintas SDK.
- Durable webhook ke sistem klien saat data perlu dikoreksi.
- Correction API yang membuat event/revision baru tanpa menimpa payload gagal.

## Bahasa yang tersedia

| SDK | Folder | Package | Queue | HTTP/FHIR | OAuth | Retry |
|---|---|---|---|---|---|---|
| Go | `sdks/go` | `satusehat` | SQLite | Ya | Ya | Ya |
| Java | `sdks/java` | `id.kemkes.satusehat` | SQLite | Ya | Ya | Ya |
| Node.js / TypeScript | `sdks/node` | `@satusehat/integration-sdk` | SQLite | Ya | Ya | Ya |
| Python | `sdks/python` | `satusehat_sdk` | SQLite | Ya | Ya | Ya |
| PHP | `sdks/php` | `satusehat/integration-sdk` | SQLite/PDO | Ya | Ya | Ya |
| .NET / C# | `sdks/dotnet` | `Satusehat.IntegrationSdk` | SQLite | Ya | Ya | Ya |

Semua SDK memakai struktur konfigurasi, status event, tabel queue, serta kebijakan error/retry yang sama.

## Release identity

v0.2.0 menambahkan monitoring, webhook ke sistem klien, dan correction workflow di atas core SDK. Integrator fasyankes tetap harus mengikuti dokumentasi resmi SATUSEHAT sebagai source of truth.

Package/namespace release:

- npm: `@satusehat/integration-sdk`
- PyPI: `satusehat-integration-sdk`
- Maven: `id.kemkes.satusehat:integration-sdk`
- Packagist: `satusehat/integration-sdk`
- NuGet: `Satusehat.IntegrationSdk`
- Go: `github.com/bofandra/satusehat-integration-sdk/sdks/go`

Sebelum package dipublikasikan ke registry publik, maintainer wajib memastikan ownership namespace/package registry, branding, dan release authority sesuai `docs/production-readiness.md` dan `RELEASE.md`.

---

# 1. Arsitektur

```text
SIMRS / SIMPUS / LIS / RIS
          |
          | enqueue FHIR event
          v
+-------------------------------+
| SATUSEHAT Integration SDK     |
|                               |
| Config                        |
| OAuth Token Cache             |
| FHIR HTTP Client              |
| SQLite Persistent Queue       |
| Worker                        |
| Rate Limiter                  |
| Retry / Backoff               |
| Error Classifier              |
+---------------+---------------+
                |
                | HTTPS + Bearer Token
                v
         SATUSEHAT FHIR API
```

Alur rekomendasi adalah **enqueue terlebih dahulu**, bukan membuat transaksi pelayanan menunggu SATUSEHAT.

```text
1. Sistem fasyankes menyimpan transaksi klinis lokal.
2. Sistem memanggil SDK `enqueue(...)`.
3. SDK menyimpan event ke SQLite.
4. Worker membaca event yang siap diproses.
5. SDK memperoleh/cache OAuth token.
6. Rate limiter mengatur throughput.
7. SDK mengirim FHIR request.
8. Response diklasifikasikan.
9. SUCCESS selesai; error retry dijadwalkan; data error menunggu koreksi.
```

Untuk jaminan atomicity penuh antara database SIMRS dan SDK, integrator dianjurkan menerapkan **Transactional Outbox** pada database aplikasi, lalu publisher memindahkan event ke SDK queue. Lihat `docs/architecture.md`. Penjelasan tanggung jawab setiap file/komponen lintas bahasa tersedia di `docs/code-structure.md`.

## Monitoring & correction loop (v0.2)

```text
SATUSEHAT --400/422--> WAITING_FOR_CORRECTION
                           |
                           v
                 Integration Console
                  | dashboard | webhook -> SIMRS
                  |                    corrected FHIR
                  +<-- POST /corrections <---+
                           |
                           v
                    new revision QUEUED
```

Run `SATUSEHAT_QUEUE_PATH=./satusehat-sdk.db python3 services/console/server.py` and open `http://127.0.0.1:8787`. See `docs/monitoring-corrections.md`.

---

# 2. Endpoint SATUSEHAT

Default konfigurasi repo:

| Environment | OAuth Base URL | FHIR Base URL |
|---|---|---|
| Sandbox | `https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1` | `https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1` |
| Production | `https://api-satusehat.kemkes.go.id/oauth2/v1` | `https://api-satusehat.kemkes.go.id/fhir-r4/v1` |

Token diperoleh dengan:

```http
POST {oauth_base_url}/accesstoken?grant_type=client_credentials
Content-Type: application/x-www-form-urlencoded

client_id=...
client_secret=...
```

Endpoint selalu dapat di-override dari konfigurasi agar perubahan platform tidak mengharuskan perubahan source code aplikasi.

Sumber resmi dicatat di `docs/reference-sources.md`.

---

# 3. Struktur Repository

```text
satusehat-integration-sdk/
├── README.md
├── LICENSE
├── NOTICE
├── SECURITY.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── VALIDATION.md
├── .editorconfig
├── .gitignore
├── .env.example
├── .github/workflows/ci.yml
│
├── docs/
│   ├── architecture.md
│   ├── code-structure.md
│   ├── data-model.md
│   ├── retry-policy.md
│   ├── security.md
│   ├── integration-guide.md
│   ├── api-contract.md
│   ├── local-development.md
│   ├── production-readiness.md
│   ├── github-publishing.md
│   └── reference-sources.md
│
├── spec/
│   ├── event.schema.json
│   ├── config.schema.json
│   ├── error-categories.json
│   └── sqlite-schema.sql
│
├── tools/
│   └── mock_satusehat.py
│
├── examples/
│   └── fhir/
│       ├── encounter.json
│       ├── condition.json
│       └── patch-status-entered-in-error.json
│
└── sdks/
    ├── go/
    ├── java/
    ├── node/
    ├── python/
    ├── php/
    └── dotnet/
```

---

# 4. Struktur Data

## 4.1 Integration Event

Semua implementasi memakai logical model berikut:

```json
{
  "event_id": "01J...",
  "organization_id": "10000001",
  "idempotency_key": "encounter:local-visit-123:create",
  "operation": "POST",
  "resource_type": "Encounter",
  "resource_id": null,
  "payload": {"resourceType": "Encounter"},
  "status": "QUEUED",
  "attempt": 0,
  "http_status": null,
  "error_category": null,
  "error_message": null,
  "created_at": "2026-08-12T14:00:00Z",
  "updated_at": "2026-08-12T14:00:00Z",
  "next_retry_at": null
}
```

Schema JSON: `spec/event.schema.json`.

## 4.2 Status

| Status | Arti |
|---|---|
| `QUEUED` | Menunggu worker |
| `PROCESSING` | Sedang dikirim |
| `SUCCESS` | Berhasil 2xx |
| `WAITING_FOR_CORRECTION` | Payload/data perlu diperbaiki |
| `RATE_LIMITED` | Terkena 429, dijadwalkan ulang |
| `RETRYING` | Error sementara/network/5xx |
| `DEAD_LETTER` | Melewati batas retry |
| `CANCELLED` | Dihentikan secara manual |

## 4.3 SQLite

Default database: `satusehat-sdk.db`.

```sql
CREATE TABLE integration_events (
  event_id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL,
  idempotency_key TEXT,
  operation TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT,
  payload_json TEXT,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 0,
  http_status INTEGER,
  error_category TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  next_retry_at TEXT
);
```

DDL lengkap ada di `spec/sqlite-schema.sql`.

---

# 5. Konfigurasi

Gunakan environment variable; **jangan commit credential**.

```bash
SATUSEHAT_ENV=sandbox
SATUSEHAT_CLIENT_ID=your-client-id
SATUSEHAT_CLIENT_SECRET=your-client-secret
SATUSEHAT_ORGANIZATION_ID=10000001
SATUSEHAT_QUEUE_PATH=./satusehat-sdk.db
SATUSEHAT_RATE_LIMIT_RPM=300
SATUSEHAT_MAX_RETRIES=5
SATUSEHAT_PROCESSING_TIMEOUT_SECONDS=300
```

Copy `.env.example` sebagai baseline.

Konfigurasi utama:

| Field | Default | Penjelasan |
|---|---:|---|
| `environment` | `sandbox` | `sandbox` / `production` |
| `organization_id` | - | Organization ID fasyankes |
| `client_id` | - | API Client ID |
| `client_secret` | - | API Client Secret |
| `queue_path` | `./satusehat-sdk.db` | Lokasi SQLite |
| `timeout_seconds` | `30` | HTTP timeout |
| `rate_limit_rpm` | `300` | Throttle lokal |
| `max_retries` | `5` | Maksimum retry per event |
| `processing_timeout_seconds` | `300` | Lease `PROCESSING`; event diproses ulang jika worker mati melewati batas ini |
| `initial_backoff_ms` | `1000` | Backoff awal |
| `max_backoff_ms` | `60000` | Backoff maksimal |

---

# 6. Cara Menggunakan

## Go

```bash
cd sdks/go
go mod tidy
go test ./...
```

```go
cfg := satusehat.ConfigFromEnv()
sdk, err := satusehat.New(cfg)
if err != nil { panic(err) }
defer sdk.Close()

payload := []byte(`{"resourceType":"Encounter","status":"finished"}`)
eventID, err := sdk.Enqueue("POST", "Encounter", "", payload)
if err != nil { panic(err) }

fmt.Println("queued:", eventID)
_, _ = sdk.ProcessOnce(context.Background(), 20)
```

Contoh runnable: `sdks/go/examples/basic/main.go`.

## Java

```bash
cd sdks/java
mvn test
```

```java
SatusehatConfig cfg = SatusehatConfig.fromEnv();
try (SatusehatSdk sdk = new SatusehatSdk(cfg)) {
    String eventId = sdk.enqueue("POST", "Encounter", null, payloadJson);
    sdk.processOnce(20);
}
```

Contoh runnable: `sdks/java/examples/BasicExample.java`. Test unit: `sdks/java/src/test/...`.

## Node.js / TypeScript

```bash
cd sdks/node
npm ci
npm test
npm run build
```

```ts
const sdk = new SatusehatSdk(SatusehatConfig.fromEnv());
const eventId = sdk.enqueue("POST", "Encounter", undefined, encounter);
await sdk.processOnce(20);
sdk.close();
```

## Python

```bash
cd sdks/python
python -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
pytest
```

```python
from satusehat_sdk import SatusehatConfig, SatusehatSdk

sdk = SatusehatSdk(SatusehatConfig.from_env())
event_id = sdk.enqueue("POST", "Encounter", payload=encounter, idempotency_key="encounter:local-visit-123:create")
sdk.process_once(limit=20)
sdk.close()
```

## PHP

```bash
cd sdks/php
composer install
composer test
```

```php
$config = Config::fromEnv();
$sdk = new SatusehatSdk($config);
$eventId = $sdk->enqueue('POST', 'Encounter', null, $encounter);
$sdk->processOnce(20);
```

## .NET

```bash
cd sdks/dotnet
dotnet restore
dotnet test
```

```csharp
var cfg = SatusehatConfig.FromEnvironment();
await using var sdk = new SatusehatSdk(cfg);
var eventId = sdk.Enqueue("POST", "Encounter", null, encounterJson);
await sdk.ProcessOnceAsync(20);
```

---

# 7. Direct Request vs Queue

## Direkomendasikan: queue

```text
SIMRS transaction -> enqueue -> response lokal cepat -> worker -> SATUSEHAT
```

Gunakan untuk data pelayanan rutin. Kegagalan SATUSEHAT tidak memblokir workflow klinis.

## Direct request

Setiap SDK juga memiliki metode low-level/direct FHIR untuk kebutuhan pencarian atau request yang memang harus sinkron.

Contoh conceptual:

```text
client.request("GET", "Patient", "123", null)
```

Direct request tetap memakai OAuth, timeout, dan retry policy.

---

# 8. Kebijakan Retry

Default:

```text
2xx        -> SUCCESS
400 / 422  -> WAITING_FOR_CORRECTION
401        -> invalidate token, ambil token baru, retry
403 / 404  -> WAITING_FOR_CORRECTION
409        -> WAITING_FOR_CORRECTION (review conflict/idempotency)
429        -> RATE_LIMITED -> Retry-After atau backoff
5xx        -> RETRYING -> exponential backoff + jitter
network    -> RETRYING -> exponential backoff + jitter
```

Setelah `max_retries`, status menjadi `DEAD_LETTER`.

Detail: `docs/retry-policy.md`.

---

# 9. Rate Limiting

SDK menggunakan local token pacing sederhana. Nilai `SATUSEHAT_RATE_LIMIT_RPM` harus disesuaikan dengan limit yang diberikan untuk organisasi. SDK **bukan pengganti** kebijakan rate limit pada API Gateway SATUSEHAT.

Jika ada banyak instance aplikasi menggunakan credential organisasi yang sama, rate limit lokal per-instance tidak dapat menjamin aggregate limit. Gunakan shared queue/worker atau koordinasi terpusat.

---

# 10. Keamanan

- Jangan masukkan Client Secret ke source code/repository.
- Gunakan secret manager pada production.
- SQLite dapat berisi payload klinis; tempatkan di storage terenkripsi dan batasi permission OS.
- Jangan mengirim payload klinis ke telemetry eksternal secara default.
- Log harus menghindari NIK, nama pasien, nilai pemeriksaan, atau isi clinical note.
- Rotasi credential mengikuti kebijakan SATUSEHAT.
- Semua request API harus HTTPS.

Lihat `SECURITY.md` dan `docs/security.md`.

---

# 11. Menjalankan Worker

Pola termudah adalah worker periodik pada proses aplikasi:

```text
while running:
    processOnce(20)
    sleep(1 second)
```

Untuk production disarankan worker terpisah dari web request SIMRS agar restart web tidak menghambat drain queue. Event yang sedang `PROCESSING` memiliki lease default 300 detik melalui `SATUSEHAT_PROCESSING_TIMEOUT_SECONDS`; jika worker mati, event menjadi siap diproses ulang setelah lease kedaluwarsa. Pada backend SQLite default, gunakan **satu worker aktif per file queue**; kebutuhan multi-worker/multi-instance sebaiknya memakai shared queue adapter.

Contoh systemd/Kubernetes dapat ditambahkan pada fase deployment sesuai stack vendor.

---

# 12. Operational Query

Contoh melihat pending event:

```sql
SELECT status, COUNT(*)
FROM integration_events
GROUP BY status;
```

Melihat dead letter:

```sql
SELECT event_id, resource_type, resource_id, attempt,
       http_status, error_category, error_message
FROM integration_events
WHERE status = 'DEAD_LETTER'
ORDER BY updated_at DESC;
```

Replay sebaiknya dilakukan setelah root cause diperbaiki. Implementasi SDK menyediakan primitive queue yang dapat dikembangkan menjadi API admin/replay.

SDK menyediakan helper dasar:

- `queueStats()` / `queue_stats()` untuk hitungan per status.
- `deadLetters()` / `dead_letters()` untuk melihat event gagal permanen.
- `requeue(event_id)` untuk mengembalikan event ke `QUEUED` setelah root cause diperbaiki.

---

# 13. Batasan Versi Awal

Repo ini sengaja menjaga core tetap generik dan tidak meng-hard-code semua Playbook SATUSEHAT.

Belum termasuk:

- mapping otomatis seluruh use case klinis;
- terminologi SNOMED/LOINC/KFA resolver;
- DICOM upload;
- distributed queue multi-node;
- UI dashboard;
- remote telemetry nasional;
- automatic dependency graph antar-resource;
- encryption-at-rest bawaan SQLite.

Komponen tersebut cocok sebagai paket/extension terpisah supaya core SDK tetap stabil.

---

# 14. Rekomendasi Integrasi ke SIMRS

```text
Database SIMRS
   |
   +-- clinical transaction
   |
   +-- transactional_outbox
              |
              v
       SDK integration_events
              |
              v
           Worker
              |
              v
          SATUSEHAT
```

Jangan menghapus outbox event sampai SDK mengembalikan `event_id`. Gunakan key bisnis/source ID untuk mencegah event ganda pada publisher.

---

# 15. Kontribusi & Governance

- Perubahan kontrak lintas bahasa harus didokumentasikan di `docs/api-contract.md`.
- Status dan schema queue harus backward compatible untuk minor release.
- Setiap SDK harus memiliki test klasifikasi error dan queue minimal.
- Release mengikuti Semantic Versioning.
- Breaking change masuk major version.

Lihat `CONTRIBUTING.md`. Checklist sebelum penggunaan produksi tersedia di `docs/production-readiness.md`.

---

# 16. Quick Start Sandbox

1. Clone repository.
2. Pilih SDK sesuai bahasa SIMRS.
3. Set credential sandbox via environment variable.
4. Jalankan test.
5. Enqueue sample `examples/fhir/encounter.json` setelah menyesuaikan reference ID dengan data sandbox Anda.
6. Jalankan worker/processOnce.
7. Periksa status event di SQLite.
8. Setelah lulus pengujian, ganti environment menjadi `production` dan gunakan credential production yang sah.

**Jangan menggunakan sample identifier/resource ID sebagai data nyata.**

Untuk pengujian tanpa credential, gunakan mock server di `tools/mock_satusehat.py`; lihat `docs/local-development.md`.

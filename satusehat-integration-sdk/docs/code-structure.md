# Penjelasan Kode & Struktur Program

Walaupun mengikuti idiom masing-masing bahasa, semua SDK memakai pemisahan tanggung jawab yang sama. Ini membuat behavior lebih mudah dibandingkan, diuji, dan dipelihara lintas bahasa.

## Peta komponen lintas bahasa

| Tanggung jawab | Go | Java | Node.js | Python | PHP | .NET |
|---|---|---|---|---|---|---|
| Konfigurasi | `config.go` | `SatusehatConfig.java` | `src/config.js` | `config.py` | `Config.php` | `SatusehatConfig.cs` |
| Status/model | `models.go` | `EventStatus.java`, `FhirResponse.java` | `src/errors.js`, `index.d.ts` | `models.py` | `EventStatus.php` | `Models.cs` |
| Error classification | `errors.go` | `ErrorClassifier.java` | `src/errors.js` | `errors.py` | `ErrorClassifier.php` | `ErrorClassifier.cs` |
| OAuth token | `auth.go` | `TokenProvider.java` | `src/auth.js` | `auth.py` | `TokenProvider.php` | `TokenProvider.cs` |
| FHIR HTTP | `http.go` | `FhirClient.java` | `src/http.js` | `http.py` | `FhirClient.php` | `FhirClient.cs` |
| SQLite queue | `queue.go` | `SQLiteQueue.java` | `src/queue.js` | `queue.py` | `SQLiteQueue.php` | `SQLiteQueue.cs` |
| Orchestrator/worker | `sdk.go` | `SatusehatSdk.java` | `src/sdk.js` | `sdk.py` | `SatusehatSdk.php` | `SatusehatSdk.cs` |

## Config

`Config` adalah satu-satunya tempat yang menentukan:

- environment sandbox/production;
- credential;
- Organization ID;
- OAuth/FHIR base URL;
- timeout;
- rate limit lokal;
- retry/backoff;
- lokasi database queue.

Endpoint tidak disebarkan/hard-code di business logic lain. Override URL tersedia agar SDK dapat dipakai untuk local mock, gateway internal, atau perubahan endpoint di masa depan.

## Token Provider

Token provider menjalankan OAuth2 `client_credentials` dan menyimpan access token **hanya di memori**. Token digunakan ulang sampai mendekati expiry. HTTP 401 menginvalidasi cache agar attempt berikutnya meminta token baru.

Credential tidak ditulis ke SQLite.

## FHIR Client

FHIR client bertugas hanya untuk transport:

1. membentuk URL resource;
2. meminta Bearer token;
3. membentuk `Authorization` dan media type;
4. mengirim HTTP request;
5. mengembalikan status, header, dan body.

Klasifikasi retry tidak diletakkan di HTTP client agar dapat dipakai sama oleh direct request maupun queue worker.

## Error Classifier

Error classifier memetakan HTTP status menjadi pasangan:

```text
error_category + retryable
```

Contoh:

```text
422 -> validation_error + false
429 -> rate_limited + true
503 -> server_error + true
```

Kontrak kategorinya juga disimpan di `spec/error-categories.json`.

## SQLite Queue

Queue melakukan persistence event sebelum request dikirim ke SATUSEHAT. Ia bertugas untuk:

- membuat event ID;
- menyimpan FHIR payload;
- mengambil event yang sudah due;
- menaikkan attempt;
- menyimpan status dan error;
- menjadwalkan `next_retry_at`.

DDL canonical ada di `spec/sqlite-schema.sql`.

Default SQLite ditujukan untuk adopsi mudah dan **satu active worker per database file**. Untuk cluster/multi-worker, pertahankan kontrak queue tetapi ganti implementasi persistence dengan shared store/queue yang memiliki atomic claim/lease.

## SDK / Worker Orchestrator

`SatusehatSdk`/`SDK` adalah façade yang digunakan aplikasi fasyankes.

```text
enqueue()
   |
   v
SQLiteQueue

processOnce()
   |
   +--> rate limiter
   +--> TokenProvider
   +--> FhirClient
   +--> ErrorClassifier
   +--> Queue status update
```

Direct `request()` melewati persistence queue tetapi tetap menggunakan OAuth, rate limiter, dan retry policy.

## Rate limiter

Limiter melakukan pacing lokal berdasarkan `requests per minute`. Ini mencegah worker menguras backlog terlalu cepat. Pada sistem dengan banyak instance dan credential organisasi yang sama, limiter harus dikoordinasikan secara terpusat; limiter per proses tidak dapat mengetahui traffic proses lain.

## Tests

Unit test fokus pada kontrak paling kritikal:

- klasifikasi error;
- queue persistence;
- status success;
- status validation error;
- 429 scheduled retry.

`tools/mock_satusehat.py` menyediakan mock OAuth + FHIR untuk local end-to-end test tanpa credential asli.

## Extension points yang disarankan

Reference implementation sengaja tidak memasukkan seluruh logic Playbook ke core transport. Extension berikut dapat dibuat tanpa mengubah kontrak dasar:

- validator profil FHIR/use case;
- terminology helper SNOMED/LOINC/KFA;
- PostgreSQL/Redis/RabbitMQ/Kafka/PubSub queue adapter;
- dependency graph antar-resource;
- OpenTelemetry exporter tanpa payload klinis;
- admin/replay API;
- DICOM integration package.

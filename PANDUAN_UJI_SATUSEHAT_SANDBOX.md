# Panduan Menjalankan SDK dan Testing Pengiriman Data ke SATUSEHAT Sandbox

Panduan ini menjelaskan tahapan dari menjalankan source code SDK lokal sampai menguji koneksi dan pengiriman data POST ke SATUSEHAT staging/sandbox.

> Catatan keamanan: jangan menulis credential, organization ID, Patient ID, atau Practitioner ID asli di file dokumentasi yang akan di-commit. Simpan nilai tersebut hanya di environment variable lokal, secret manager, atau mekanisme secret CI.

## 1. Informasi Sandbox

Gunakan environment SATUSEHAT staging/sandbox:

| Key | Value |
|---|---|
| `SATUSEHAT_ENV` | `sandbox` |
| `SATUSEHAT_ORGANIZATION_ID` | Diisi dari credential sandbox lokal |
| `SATUSEHAT_CLIENT_ID` | Diisi dari credential sandbox lokal |
| `SATUSEHAT_CLIENT_SECRET` | Diisi dari credential sandbox lokal |
| OAuth base URL | `https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1` |
| FHIR base URL | `https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1` |

Endpoint di atas mengikuti konfigurasi repo dan dokumentasi resmi SATUSEHAT:

- Akses token: `https://satusehat.kemkes.go.id/platform/docs/id/api-catalogue/authentication/apis/token/`
- Endpoint REST/FHIR: `https://satusehat.kemkes.go.id/platform/docs/id/master-data/master-patient-index/rest-api-mpi/`

## 2. Resource yang Sudah Dapat Diakomodasi Kode Saat Ini

SDK ini adalah generic FHIR client, bukan mapper khusus per resource. Method `request()` dan `enqueue()` menerima `resource_type` string, lalu membentuk request ke endpoint FHIR:

```text
{SATUSEHAT_FHIR_BASE_URL}/{resource_type}
```

Artinya, kode SDK dapat mengakomodasi resource FHIR apa pun yang endpoint dan payload-nya valid di SATUSEHAT. Validasi business rule, profil FHIR, dan reference antar-resource tetap dilakukan oleh SATUSEHAT.

Resource yang sudah ada contoh/test live di repo:

| Resource | Bukti di repo | Catatan |
|---|---|---|
| `Organization` | `tools/sandbox_write_matrix.sh` | POST smoke test lintas SDK tanpa dependency Patient/Practitioner. |
| `Location` | `tools/sandbox_clinical_matrix.sh` | Bagian clinical chain; membutuhkan organization credential. |
| `Encounter` | `examples/fhir/encounter.json`, `tools/sandbox_clinical_matrix.sh` | Membutuhkan Patient, Practitioner, Location, dan Organization sandbox valid. |
| `Condition` | `examples/fhir/condition.json`, `tools/sandbox_clinical_matrix.sh` | Membutuhkan Patient, Practitioner, dan Encounter valid. |
| `Observation` | `tools/sandbox_clinical_matrix.sh` | Membutuhkan Patient, Practitioner, dan Encounter valid. |

Operation yang didukung SDK:

- `POST` untuk create resource.
- `GET` untuk read/search sederhana.
- `PUT` dan `PATCH` untuk update, dengan `resource_id` wajib.

## 3. Prasyarat

Minimal untuk testing sandbox:

- Akses internet ke host `api-satusehat-stg.dto.kemkes.go.id`.
- Credential sandbox aktif.
- Untuk clinical POST matrix: Patient dan Practitioner sandbox yang valid.

Runtime per SDK:

| SDK | Runtime minimum | Catatan |
|---|---|---|
| Python | Python 3.10+ | Dipakai juga oleh `tools/sandbox_contract.py`. |
| Node.js / TypeScript | Node.js sesuai `sdks/node/package.json` | Gunakan Node `20`, `22`, atau `24`; hindari Node `23` karena di luar engine range package. |
| Go | Go 1.23+ | Membutuhkan CGO untuk SQLite driver default. |
| Java | Java 21+ dan Maven | Maven mengambil dependency SQLite JDBC. |
| PHP | PHP 8.2+, Composer, `curl`, `pdo`, `pdo_sqlite` | Pastikan `php -v` tidak masih PHP 7.x. |
| .NET / C# | .NET 8 SDK | Menggunakan `Microsoft.Data.Sqlite`. |

## 4. Masuk ke Root Repository

Jalankan perintah dari root repository:

```bash
cd /Users/dto/code/integration-satusehat-sdk/satusehat-integration-sdk
```

File yang akan dipakai di panduan ini:

- `sdks/python/src/satusehat_sdk/`: source code Python SDK.
- `sdks/python/examples/basic.py`: contoh enqueue dan process queue.
- `sdks/node/src/`: source code Node.js SDK.
- `sdks/node/examples/basic.mjs`: contoh enqueue dan process queue.
- `sdks/go/`: source code Go SDK dan contoh `sdks/go/examples/basic`.
- `sdks/java/`: source code Java SDK dan contoh `sdks/java/examples/BasicExample.java`.
- `sdks/php/`: source code PHP SDK dan contoh `sdks/php/examples/basic.php`.
- `sdks/dotnet/`: source code .NET SDK dan contoh `sdks/dotnet/examples/Program.cs`.
- `tools/mock_satusehat.py`: mock server lokal.
- `tools/sandbox_contract.py`: test kontrak read-only dan optional write ke SATUSEHAT sandbox.
- `tools/sandbox_write_matrix.sh`: POST `Organization` lintas SDK.
- `tools/sandbox_clinical_matrix.sh`: POST clinical chain lintas SDK.
- `examples/fhir/encounter.json`: fixture FHIR contoh.
- `examples/fhir/condition.json`: fixture FHIR contoh.

## 5. Export Environment Variable Lokal

Jangan tulis nilai credential asli ke file Markdown. Export langsung di shell session atau simpan di `.env` lokal yang tidak di-commit.

Contoh `.env` lokal dengan placeholder:

```bash
cat > .env <<'EOF'
SATUSEHAT_ENV=sandbox
SATUSEHAT_CLIENT_ID=<isi-client-id-sandbox>
SATUSEHAT_CLIENT_SECRET=<isi-client-secret-sandbox>
SATUSEHAT_ORGANIZATION_ID=<isi-organization-id-sandbox>
SATUSEHAT_QUEUE_PATH=/tmp/satusehat-sdk-stg.db
SATUSEHAT_TIMEOUT_SECONDS=30
SATUSEHAT_RATE_LIMIT_RPM=300
SATUSEHAT_MAX_RETRIES=5
SATUSEHAT_PROCESSING_TIMEOUT_SECONDS=300
SATUSEHAT_INITIAL_BACKOFF_MS=1000
SATUSEHAT_MAX_BACKOFF_MS=60000
SATUSEHAT_SANDBOX_ENABLE_WRITES=false
SATUSEHAT_SANDBOX_WRITE_FIXTURE=/tmp/satusehat-encounter-write.json
SATUSEHAT_SANDBOX_PATIENT_ID=<isi-patient-id-sandbox>
SATUSEHAT_SANDBOX_PATIENT_NAME=<isi-patient-name-sandbox>
SATUSEHAT_SANDBOX_PRACTITIONER_ID=<isi-practitioner-id-sandbox>
SATUSEHAT_SANDBOX_PRACTITIONER_NAME=<isi-practitioner-name-sandbox>
EOF
```

Load environment variable:

```bash
set -a
source .env
set +a
```

Pastikan variable wajib sudah terisi tanpa mencetak nilainya:

```bash
for name in \
  SATUSEHAT_ENV \
  SATUSEHAT_CLIENT_ID \
  SATUSEHAT_CLIENT_SECRET \
  SATUSEHAT_ORGANIZATION_ID \
  SATUSEHAT_SANDBOX_PATIENT_ID \
  SATUSEHAT_SANDBOX_PATIENT_NAME \
  SATUSEHAT_SANDBOX_PRACTITIONER_ID \
  SATUSEHAT_SANDBOX_PRACTITIONER_NAME; do
  if [ -n "${!name:-}" ]; then
    printf '%s=present\n' "$name"
  else
    printf '%s=missing\n' "$name"
  fi
done
```

## 6. Install, Build, dan Validasi Source Code Semua SDK

Jalankan dari root repository. Pilih SDK yang ingin diuji, atau jalankan semua jika toolchain lengkap.

### Python

```bash
cd sdks/python
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -e '.[dev]'
python3 -m pytest -q
cd ../..
```

### Node.js / TypeScript

```bash
cd sdks/node
npm ci
npm test
npm run build
cd ../..
```

Jika `node -v` menampilkan Node `23.x`, gunakan Node versi lain yang masuk range package, misalnya Node `20`, `22`, atau `24`.

### Go

```bash
cd sdks/go
go mod tidy
go test ./...
cd ../..
```

### Java

```bash
cd sdks/java
mvn test
cd ../..
```

### PHP

```bash
cd sdks/php
composer install
composer test
cd ../..
```

Jika default `php` masih PHP 7.x tetapi PHP 8 tersedia di path lain, jalankan Composer dengan PHP 8 yang sama, misalnya:

```bash
PHP_BIN=/path/to/php8
COMPOSER_BIN="$(command -v composer)"
cd sdks/php
"$PHP_BIN" "$COMPOSER_BIN" install
"$PHP_BIN" "$COMPOSER_BIN" test
cd ../..
```

### .NET / C#

```bash
cd sdks/dotnet
dotnet restore
dotnet build
cd ../..
```

### Semua SDK via Makefile

```bash
make validate
```

Target Makefile yang tersedia:

```bash
make python
make node
make go
make java
make php
make dotnet
```

Jika validasi sukses, source code SDK lokal sudah bisa dijalankan.

## 7. Jalankan Contoh SDK dengan Mock Lokal

Tahap ini memastikan flow OAuth, enqueue, queue SQLite, dan worker berjalan tanpa menyentuh SATUSEHAT sungguhan.

Terminal 1:

```bash
python3 tools/mock_satusehat.py
```

Terminal 2:

```bash
set -a
source .env
set +a

export SATUSEHAT_OAUTH_BASE_URL=http://127.0.0.1:8765/oauth2/v1
export SATUSEHAT_FHIR_BASE_URL=http://127.0.0.1:8765/fhir-r4/v1
```

Jalankan contoh sesuai SDK.

### Python

```bash
PYTHONPATH=sdks/python/src python3 sdks/python/examples/basic.py
```

### Node.js / TypeScript

```bash
cd sdks/node
npm ci
node examples/basic.mjs
cd ../..
```

### Go

```bash
cd sdks/go
go mod tidy
go run ./examples/basic
cd ../..
```

### Java

```bash
cd sdks/java
mvn -q -DskipTests package
mkdir -p /tmp/satusehat-java-example
SQLITE_JDBC_JAR="$(find "$HOME/.m2/repository" /private/tmp/satusehat-m2 -name 'sqlite-jdbc-*.jar' 2>/dev/null | sort | tail -n 1)"
SLF4J_API_JAR="$(find "$HOME/.m2/repository" /private/tmp/satusehat-m2 -name 'slf4j-api-*.jar' 2>/dev/null | sort | tail -n 1)"
javac -cp "target/classes:$SQLITE_JDBC_JAR:$SLF4J_API_JAR" -d /tmp/satusehat-java-example examples/BasicExample.java
java -cp "/tmp/satusehat-java-example:target/classes:$SQLITE_JDBC_JAR:$SLF4J_API_JAR" BasicExample
cd ../..
```

### PHP

```bash
cd sdks/php
composer install
php examples/basic.php
cd ../..
```

Gunakan PHP 8.2+ untuk command PHP. Jika perlu, panggil binary PHP 8 secara eksplisit.

### .NET / C#

```bash
tmpdir="$(mktemp -d)"
cp sdks/dotnet/examples/Program.cs "$tmpdir/Program.cs"
cat > "$tmpdir/Example.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="/Users/dto/code/integration-satusehat-sdk/satusehat-integration-sdk/sdks/dotnet/Satusehat.IntegrationSdk.csproj" />
  </ItemGroup>
</Project>
EOF
cd sdks/dotnet
dotnet run --project "$tmpdir/Example.csproj" --no-launch-profile
cd ../..
rm -rf "$tmpdir"
```

Output yang diharapkan untuk setiap SDK:

```text
queued <event-id>
processed 1
```

Setelah selesai uji mock, hapus override URL agar tahap berikutnya kembali ke sandbox resmi:

```bash
unset SATUSEHAT_OAUTH_BASE_URL
unset SATUSEHAT_FHIR_BASE_URL
```

## 8. Uji Credential Sandbox Tanpa Write

Repo menyediakan `tools/sandbox_contract.py` sebagai baseline contract tool berbasis Python. Tahap ini aman karena hanya:

1. Mengambil token OAuth dengan `client_credentials`.
2. Memanggil FHIR `metadata`.
3. Melewati optional write.

```bash
set -a
source .env
set +a

export SATUSEHAT_SANDBOX_ENABLE_WRITES=false
PYTHONPATH=sdks/python/src python3 tools/sandbox_contract.py
```

Output sukses:

```json
{
  "status": "passed",
  "environment": "sandbox",
  "checks": [
    {
      "name": "oauth_client_credentials",
      "status": "passed"
    },
    {
      "name": "fhir_metadata_read",
      "status": "passed",
      "http_status": 200
    },
    {
      "name": "optional_write",
      "status": "skipped"
    }
  ]
}
```

Alternatif via `Makefile`:

```bash
make sandbox-contract
```

## 9. All SDK POST Matrix

Gunakan matrix berikut untuk actual POST ke SATUSEHAT sandbox di semua SDK.

Required environment variable:

- `SATUSEHAT_ENV=sandbox`
- `SATUSEHAT_CLIENT_ID`
- `SATUSEHAT_CLIENT_SECRET`
- `SATUSEHAT_ORGANIZATION_ID`
- `SATUSEHAT_SANDBOX_PATIENT_ID`
- `SATUSEHAT_SANDBOX_PATIENT_NAME`
- `SATUSEHAT_SANDBOX_PRACTITIONER_ID`
- `SATUSEHAT_SANDBOX_PRACTITIONER_NAME`

### Organization POST Smoke Matrix

Matrix ini mengirim `Organization` lintas SDK. Cocok untuk validasi POST awal karena tidak membutuhkan Patient dan Practitioner.

```bash
set -a
source .env
set +a

tools/sandbox_write_matrix.sh
```

Resource yang di-POST setiap platform:

1. `Organization`

### Clinical POST Matrix

Matrix ini mengirim clinical chain lintas SDK dan membutuhkan Patient serta Practitioner sandbox yang valid.

Command:

```bash
set -a
source .env
set +a

tools/sandbox_clinical_matrix.sh
```

Default platform yang dijalankan:

- Python.
- Node.js.
- Go.
- Java.
- PHP.
- .NET.

Resource yang di-POST setiap platform:

1. `Location`
2. `Encounter`
3. `Condition`
4. `Observation`

Expected success message:

```text
All live SATUSEHAT sandbox clinical validations passed.
```

Jika ingin menjalankan satu platform saja:

```bash
tools/sandbox_clinical_matrix.sh python
tools/sandbox_clinical_matrix.sh node
tools/sandbox_clinical_matrix.sh go
tools/sandbox_clinical_matrix.sh java
tools/sandbox_clinical_matrix.sh php
tools/sandbox_clinical_matrix.sh dotnet
```

Jika runtime default tidak sesuai, override binary lewat environment variable:

```bash
NODE_BIN=/path/to/node24 tools/sandbox_clinical_matrix.sh node
PHP_BIN=/path/to/php8 tools/sandbox_clinical_matrix.sh php
```

## 10. Optional Single-Fixture Write Test dengan Python Contract Tool

Bagian ini opsional dan memakai `tools/sandbox_contract.py`, sehingga jalurnya Python-only. Untuk POST lintas SDK, gunakan section 9.

Untuk uji POST satu resource via contract tool, siapkan fixture di luar repo:

```bash
cp examples/fhir/encounter.json /tmp/satusehat-encounter-write.json
```

Edit `/tmp/satusehat-encounter-write.json`, lalu sesuaikan minimal:

```json
{
  "resourceType": "Encounter",
  "status": "finished",
  "class": {
    "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
    "code": "AMB",
    "display": "ambulatory"
  },
  "subject": {
    "reference": "Patient/<sandbox-patient-id-yang-valid>"
  },
  "serviceProvider": {
    "reference": "Organization/<sandbox-organization-id-yang-valid>"
  }
}
```

Validasi JSON:

```bash
python3 -m json.tool /tmp/satusehat-encounter-write.json >/dev/null
```

Aktifkan optional write dan jalankan contract tool:

```bash
set -a
source .env
set +a

export SATUSEHAT_SANDBOX_ENABLE_WRITES=true
export SATUSEHAT_SANDBOX_WRITE_FIXTURE=/tmp/satusehat-encounter-write.json

PYTHONPATH=sdks/python/src python3 tools/sandbox_contract.py
```

Jika sukses, output akan berisi:

```json
{
  "name": "optional_write",
  "status": "passed",
  "http_status": 201
}
```

`http_status` bisa berbeda selama masih `2xx`.

Jika gagal dengan `400` atau `422`, cek isi payload. Untuk melihat response body secara lebih jelas, jalankan debug script berikut:

```bash
PYTHONPATH=sdks/python/src python3 - <<'PY'
import json
import os
from pathlib import Path
from satusehat_sdk import SatusehatConfig, SatusehatSdk

fixture = Path(os.environ["SATUSEHAT_SANDBOX_WRITE_FIXTURE"])
payload = json.loads(fixture.read_text(encoding="utf-8"))
resource_type = payload["resourceType"]

sdk = SatusehatSdk(SatusehatConfig.from_env())
try:
    response = sdk.request("POST", resource_type, payload=payload)
    print("HTTP", response.status_code)
    print(response.body[:4000])
finally:
    sdk.close()
PY
```

## 11. Testing Pengiriman Data Lewat Queue SDK

Tahap ini menguji flow yang direkomendasikan untuk aplikasi SIMRS/SIMPUS:

```text
enqueue -> SQLite queue -> process_once worker -> SATUSEHAT FHIR API
```

Semua SDK menyediakan konsep yang sama:

| SDK | Enqueue | Process worker | Queue stats |
|---|---|---|---|
| Python | `sdk.enqueue(...)` | `sdk.process_once(20)` | `sdk.queue_stats()` |
| Node.js / TypeScript | `sdk.enqueue(...)` | `await sdk.processOnce(20)` | `sdk.queueStats()` |
| Go | `sdk.Enqueue(...)` atau `sdk.EnqueueIdempotent(...)` | `sdk.ProcessOnce(ctx, 20)` | `sdk.QueueStats()` |
| Java | `sdk.enqueue(...)` atau `sdk.enqueueIdempotent(...)` | `sdk.processOnce(20)` | `sdk.queueStats()` |
| PHP | `$sdk->enqueue(...)` | `$sdk->processOnce(20)` | `$sdk->queueStats()` |
| .NET / C# | `sdk.Enqueue(...)` | `await sdk.ProcessOnceAsync(20)` | `sdk.QueueStats()` |

Contoh runnable yang memakai queue tersedia di:

| SDK | Contoh |
|---|---|
| Python | `sdks/python/examples/basic.py` |
| Node.js / TypeScript | `sdks/node/examples/basic.mjs` |
| Go | `sdks/go/examples/basic` |
| Java | `sdks/java/examples/BasicExample.java` |
| PHP | `sdks/php/examples/basic.php` |
| .NET / C# | `sdks/dotnet/examples/Program.cs` |

Contoh manual Python:

```bash
set -a
source .env
set +a

export SATUSEHAT_SANDBOX_WRITE_FIXTURE=/tmp/satusehat-encounter-write.json

PYTHONPATH=sdks/python/src python3 - <<'PY'
import json
import os
import time
from pathlib import Path
from satusehat_sdk import SatusehatConfig, SatusehatSdk

fixture = Path(os.environ["SATUSEHAT_SANDBOX_WRITE_FIXTURE"])
payload = json.loads(fixture.read_text(encoding="utf-8"))
resource_type = payload["resourceType"]
idempotency_key = f"sandbox:{resource_type}:manual:{int(time.time())}"

sdk = SatusehatSdk(SatusehatConfig.from_env())
try:
    event_id = sdk.enqueue("POST", resource_type, payload=payload, idempotency_key=idempotency_key)
    processed = sdk.process_once(20)

    print("event_id", event_id)
    print("processed", processed)
    print("queue_stats", sdk.queue_stats())
finally:
    sdk.close()
PY
```

Lihat status event terakhir di SQLite:

```bash
python3 - <<'PY'
import os
import sqlite3

db_path = os.environ.get("SATUSEHAT_QUEUE_PATH", "/tmp/satusehat-sdk-stg.db")
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
rows = conn.execute("""
SELECT event_id, operation, resource_type, status, attempt, http_status,
       error_category, substr(coalesce(error_message, ''), 1, 1000) AS error_message,
       updated_at
FROM integration_events
ORDER BY updated_at DESC
LIMIT 5
""").fetchall()

for row in rows:
    print(dict(row))
PY
```

Interpretasi status:

| Status | Arti |
|---|---|
| `SUCCESS` | SATUSEHAT mengembalikan HTTP `2xx`; pengiriman berhasil. |
| `WAITING_FOR_CORRECTION` | Biasanya HTTP `400`, `403`, `404`, `409`, atau `422`; payload/data referensi perlu diperbaiki. |
| `RATE_LIMITED` | SATUSEHAT mengembalikan `429`; SDK menjadwalkan retry. |
| `RETRYING` | Network error atau HTTP `5xx`; SDK menjadwalkan retry. |
| `DEAD_LETTER` | Event melewati batas retry dan perlu investigasi manual. |

## 12. Jalankan Validasi Semua SDK

Bagian ini opsional karena membutuhkan toolchain lintas bahasa.

```bash
make validate
```

Atau jalankan per SDK:

```bash
make python
make node
make go
make java
make php
make dotnet
```

## 13. Troubleshooting

OAuth gagal:

- Pastikan `.env` sudah di-load di terminal yang sama.
- Pastikan `SATUSEHAT_ENV=sandbox`.
- Pastikan tidak ada override `SATUSEHAT_OAUTH_BASE_URL` yang masih mengarah ke mock.
- HTTP `401` biasanya berarti `client_id` atau `client_secret` salah/tidak aktif.

FHIR metadata gagal:

- Pastikan akses internet ke `api-satusehat-stg.dto.kemkes.go.id`.
- Pastikan tidak ada override `SATUSEHAT_FHIR_BASE_URL`.
- HTTP `403` bisa berarti credential tidak punya akses resource.

Write test gagal `400` atau `422`:

- Cek `OperationOutcome` dari response body.
- Pastikan `resourceType` cocok dengan endpoint.
- Pastikan semua reference ada dan valid di sandbox, terutama `Patient/...`, `Practitioner/...`, dan `Organization/...`.
- Lengkapi payload sesuai profil/use case SATUSEHAT. Fixture minimal belum tentu valid untuk semua validasi SATUSEHAT.

Queue tidak memproses event:

- Pastikan `sdk.process_once(20)` dipanggil.
- Cek `SATUSEHAT_QUEUE_PATH`.
- Cek status event dengan query SQLite di bagian 11.
- Jika status `RETRYING` atau `RATE_LIMITED`, tunggu sampai `next_retry_at`, lalu panggil `process_once` lagi.

## 14. Bersihkan Artefak Lokal Setelah Testing

Jika sudah selesai dan tidak perlu menyimpan queue lokal:

```bash
rm -f /tmp/satusehat-sdk-stg.db /tmp/satusehat-sdk-stg.db-wal /tmp/satusehat-sdk-stg.db-shm
rm -f /tmp/satusehat-encounter-write.json
```

Jangan hapus data queue production tanpa prosedur backup dan approval operasional.

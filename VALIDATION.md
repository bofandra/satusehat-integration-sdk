# Validation Notes — v0.1.0

Tanggal pemeriksaan: 2026-08-12.

## Pemeriksaan yang dilakukan pada workspace pembuatan

- Python: unit test `pytest` — 6 test lulus.
- Python: `compileall` lulus.
- Node.js: syntax check seluruh source/test lulus.
- Node.js: unit test dan mock end-to-end telah dijalankan pada tahap pengembangan menggunakan compatibility shim lokal untuk dependency SQLite; shim tersebut **tidak** disertakan dalam repository.
- Java: seluruh source `src/main` berhasil dikompilasi dengan `javac --release 21`.
- PHP: `php -l` seluruh source, test, dan example lulus.
- Go: `gofmt` bersih dan source telah diperiksa; CI repository menjalankan `go test ./...` setelah dependency tersedia.
- JSON, XML, dan YAML repository berhasil diparse.
- Python dan Node.js telah diuji terhadap mock OAuth + FHIR lokal (`tools/mock_satusehat.py`) pada tahap pengembangan.

## Pemeriksaan yang didelegasikan ke GitHub Actions

GitHub Actions `.github/workflows/ci.yml` menjalankan build/test pada environment bersih untuk Python, Go, Node.js, Java, PHP, dan .NET. Ini penting khususnya untuk dependency yang tidak tersedia pada container pembuatan offline, misalnya Maven/NuGet/Go module registry.

## Catatan

Status repository adalah **reference implementation/draft**. Sebelum dipakai pada production, selesaikan checklist di `docs/production-readiness.md`, lakukan integration test dengan credential sandbox resmi, security review, load test, serta approval governance Kementerian Kesehatan.

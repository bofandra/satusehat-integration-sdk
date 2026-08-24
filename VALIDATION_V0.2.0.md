# Validation Evidence — v0.2.0

Validated locally on 2026-08-23 for the monitoring/correction change set:

- `python3 -m unittest tests/test_console.py -v`: **5 passed**.
- existing Python SDK regression suite: **9 passed**.
- Node.js source syntax (`node --check`): **passed**.
- PHP source syntax lint: **passed**.
- JSON schemas: **parsed successfully**.
- Integration Console HTTP smoke test: dashboard `200`, HTTP-400 correction appears in worklist, corrected payload creates revision 2 with `QUEUED` status.
- Compatibility check: a corrected revision created by the console is consumed by the existing Python SDK queue worker and reaches `SUCCESS` with a mocked HTTP 201 response.
- Webhook test: correction notification delivered to a mock client and HMAC signature verified.

Not executed in this local runtime because required toolchains/dependencies were unavailable offline:

- Go full `go test` (dependency download unavailable in runtime).
- Java Maven tests (`mvn` unavailable).
- .NET build (`dotnet` unavailable).
- Node runtime tests requiring native `better-sqlite3` install (network/native install unavailable); syntax validation passed.

GitHub Actions remains the clean-environment validation gate for all six SDK languages.

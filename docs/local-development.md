# Local Development with Mock Server

The repo includes `tools/mock_satusehat.py` to exercise OAuth + FHIR calls without real credentials.

Run:

```bash
python3 tools/mock_satusehat.py
```

Then configure any SDK:

```bash
export SATUSEHAT_CLIENT_ID=mock
export SATUSEHAT_CLIENT_SECRET=mock
export SATUSEHAT_ORGANIZATION_ID=10000001
export SATUSEHAT_OAUTH_BASE_URL=http://127.0.0.1:8765/oauth2/v1
export SATUSEHAT_FHIR_BASE_URL=http://127.0.0.1:8765/fhir-r4/v1
```

The mock is **not** a FHIR validator and must never be used as a production service. Its purpose is deterministic SDK development.

## Run examples against the mock

With the environment variables above set, open a second terminal.

### Python

```bash
cd sdks/python
PYTHONPATH=src python3 examples/basic.py
```

### Node.js

```bash
cd sdks/node
npm ci
node examples/basic.mjs
```

### Go

```bash
cd sdks/go
go mod tidy
go run ./examples/basic
```

### Ruby

```bash
cd sdks/ruby
bundle install
ruby -Ilib examples/basic.rb
```

The other SDKs can use the same two override URLs. Follow their SDK README/build commands, then call `enqueue` + `processOnce`/`process_once` with any sanitized FHIR JSON.

## Simulating errors

The mock server supports a forced FHIR response status through the request header `X-Mock-Status`; this is useful when exercising a low-level HTTP client manually. Python and Node unit tests directly inject/simulate 422/429 responses for deterministic queue-state tests.

The mock deliberately does not reproduce SATUSEHAT business validation, terminology validation, profile validation, or authorization rules.

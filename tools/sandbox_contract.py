#!/usr/bin/env python3
"""SATUSEHAT sandbox contract check for release gates.

The default check is read-only: OAuth token retrieval plus an authenticated FHIR
metadata request against sandbox. Optional write checks must be explicitly
enabled by maintainers with non-PHI sandbox fixtures.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_SDK_SRC = ROOT / "sdks" / "python" / "src"
sys.path.insert(0, str(PYTHON_SDK_SRC))

from satusehat_sdk import SatusehatConfig, SatusehatSdk  # noqa: E402

SANDBOX_HOST = "api-satusehat-stg.dto.kemkes.go.id"
PRODUCTION_HOST = "api-satusehat.kemkes.go.id"


def _fail(message: str) -> None:
    print(json.dumps({"status": "failed", "message": message}, indent=2))
    raise SystemExit(1)


def _assert_sandbox_only(config: SatusehatConfig) -> None:
    if config.environment != "sandbox":
        _fail("SATUSEHAT_ENV must be sandbox for release contract tests")
    endpoints = [config.oauth_base_url, config.fhir_base_url]
    if any(PRODUCTION_HOST in endpoint for endpoint in endpoints):
        _fail("production SATUSEHAT endpoints are not allowed in contract tests")
    allow_override = os.environ.get("SATUSEHAT_ALLOW_CONTRACT_ENDPOINT_OVERRIDE") == "true"
    if not allow_override and any(SANDBOX_HOST not in endpoint for endpoint in endpoints):
        _fail("contract tests must use official sandbox endpoints unless override is explicitly enabled")


def _optional_write_check(sdk: SatusehatSdk) -> dict:
    if os.environ.get("SATUSEHAT_SANDBOX_ENABLE_WRITES") != "true":
        return {"name": "optional_write", "status": "skipped"}

    fixture_path = Path(os.environ.get("SATUSEHAT_SANDBOX_WRITE_FIXTURE", "examples/fhir/encounter.json"))
    if not fixture_path.is_absolute():
        fixture_path = ROOT / fixture_path
    if not fixture_path.exists():
        _fail(f"write fixture not found: {fixture_path}")
    payload = json.loads(fixture_path.read_text(encoding="utf-8"))
    resource_type = payload.get("resourceType")
    if not resource_type:
        _fail("write fixture must contain resourceType")
    response = sdk.request("POST", resource_type, payload=payload)
    if not 200 <= response.status_code <= 299:
        _fail(f"optional write check failed with HTTP {response.status_code}")
    return {"name": "optional_write", "status": "passed", "http_status": response.status_code}


def main() -> int:
    required = ["SATUSEHAT_CLIENT_ID", "SATUSEHAT_CLIENT_SECRET", "SATUSEHAT_ORGANIZATION_ID"]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        _fail("missing required sandbox secrets: " + ", ".join(missing))

    config = SatusehatConfig.from_env()
    _assert_sandbox_only(config)
    sdk = SatusehatSdk(config)
    checks: list[dict] = []
    try:
        try:
            token = sdk.tokens.get_token()
            if not token:
                _fail("OAuth token was empty")
            checks.append({"name": "oauth_client_credentials", "status": "passed"})

            response = sdk.fhir.request_once("GET", "metadata")
            if not 200 <= response.status_code <= 299:
                _fail(f"FHIR metadata check failed with HTTP {response.status_code}")
            checks.append({"name": "fhir_metadata_read", "status": "passed", "http_status": response.status_code})

            checks.append(_optional_write_check(sdk))
        except Exception as exc:
            _fail(f"contract check failed: {exc}")
    finally:
        sdk.close()

    print(json.dumps({
        "status": "passed",
        "environment": config.environment,
        "oauth_base_url": config.oauth_base_url,
        "fhir_base_url": config.fhir_base_url,
        "checks": checks,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

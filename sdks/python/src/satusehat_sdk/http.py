from __future__ import annotations
import json
import urllib.request
import urllib.error
from .auth import TokenProvider
from .config import SatusehatConfig
from .models import FhirResponse

class FhirClient:
    def __init__(self, config: SatusehatConfig, token_provider: TokenProvider):
        self.config = config
        self.tokens = token_provider

    def request_once(self, method: str, resource_type: str, resource_id: str | None = None, payload=None) -> FhirResponse:
        method = method.upper()
        url = f"{self.config.fhir_base_url}/{resource_type}"
        if resource_id:
            url += f"/{resource_id}"
        data = None
        content_type = "application/fhir+json"
        if payload is not None:
            data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            if method == "PATCH":
                content_type = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.tokens.get_token()}",
            "Accept": "application/fhir+json, application/json",
            "Content-Type": content_type,
        })
        try:
            with urllib.request.urlopen(req, timeout=self.config.timeout_seconds) as resp:
                return FhirResponse(resp.status, resp.read().decode("utf-8", errors="replace"), dict(resp.headers.items()))
        except urllib.error.HTTPError as exc:
            return FhirResponse(exc.code, exc.read().decode("utf-8", errors="replace"), dict(exc.headers.items()))

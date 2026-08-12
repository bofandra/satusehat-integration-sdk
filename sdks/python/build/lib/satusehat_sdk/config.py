from __future__ import annotations
from dataclasses import dataclass
import os

SANDBOX_OAUTH = "https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1"
SANDBOX_FHIR = "https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1"
PRODUCTION_OAUTH = "https://api-satusehat.kemkes.go.id/oauth2/v1"
PRODUCTION_FHIR = "https://api-satusehat.kemkes.go.id/fhir-r4/v1"

@dataclass(frozen=True)
class SatusehatConfig:
    client_id: str
    client_secret: str
    organization_id: str
    environment: str = "sandbox"
    queue_path: str = "./satusehat-sdk.db"
    timeout_seconds: int = 30
    rate_limit_rpm: int = 300
    max_retries: int = 5
    processing_timeout_seconds: int = 300
    initial_backoff_ms: int = 1000
    max_backoff_ms: int = 60000
    oauth_base_url_override: str | None = None
    fhir_base_url_override: str | None = None

    def __post_init__(self):
        if self.environment not in ("sandbox", "production"):
            raise ValueError("environment must be sandbox or production")
        if not self.client_id or not self.client_secret or not self.organization_id:
            raise ValueError("client_id, client_secret, and organization_id are required")
        if self.rate_limit_rpm <= 0 or self.max_retries <= 0 or self.processing_timeout_seconds <= 0:
            raise ValueError("rate_limit_rpm, max_retries, and processing_timeout_seconds must be > 0")

    @property
    def oauth_base_url(self) -> str:
        if self.oauth_base_url_override:
            return self.oauth_base_url_override.rstrip("/")
        return SANDBOX_OAUTH if self.environment == "sandbox" else PRODUCTION_OAUTH

    @property
    def fhir_base_url(self) -> str:
        if self.fhir_base_url_override:
            return self.fhir_base_url_override.rstrip("/")
        return SANDBOX_FHIR if self.environment == "sandbox" else PRODUCTION_FHIR

    @classmethod
    def from_env(cls) -> "SatusehatConfig":
        return cls(
            client_id=os.environ.get("SATUSEHAT_CLIENT_ID", ""),
            client_secret=os.environ.get("SATUSEHAT_CLIENT_SECRET", ""),
            organization_id=os.environ.get("SATUSEHAT_ORGANIZATION_ID", ""),
            environment=os.environ.get("SATUSEHAT_ENV", "sandbox").lower(),
            queue_path=os.environ.get("SATUSEHAT_QUEUE_PATH", "./satusehat-sdk.db"),
            timeout_seconds=int(os.environ.get("SATUSEHAT_TIMEOUT_SECONDS", "30")),
            rate_limit_rpm=int(os.environ.get("SATUSEHAT_RATE_LIMIT_RPM", "300")),
            max_retries=int(os.environ.get("SATUSEHAT_MAX_RETRIES", "5")),
            processing_timeout_seconds=int(os.environ.get("SATUSEHAT_PROCESSING_TIMEOUT_SECONDS", "300")),
            initial_backoff_ms=int(os.environ.get("SATUSEHAT_INITIAL_BACKOFF_MS", "1000")),
            max_backoff_ms=int(os.environ.get("SATUSEHAT_MAX_BACKOFF_MS", "60000")),
            oauth_base_url_override=os.environ.get("SATUSEHAT_OAUTH_BASE_URL"),
            fhir_base_url_override=os.environ.get("SATUSEHAT_FHIR_BASE_URL"),
        )

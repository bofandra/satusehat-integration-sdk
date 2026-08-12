from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from typing import Mapping

class EventStatus(str, Enum):
    QUEUED = "QUEUED"
    PROCESSING = "PROCESSING"
    SUCCESS = "SUCCESS"
    WAITING_FOR_CORRECTION = "WAITING_FOR_CORRECTION"
    RATE_LIMITED = "RATE_LIMITED"
    RETRYING = "RETRYING"
    DEAD_LETTER = "DEAD_LETTER"
    CANCELLED = "CANCELLED"

@dataclass
class FhirResponse:
    status_code: int
    body: str
    headers: Mapping[str, str]

@dataclass
class TransportFailure:
    message: str

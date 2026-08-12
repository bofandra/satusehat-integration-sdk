import os
from pathlib import Path
from satusehat_sdk import SatusehatConfig, SatusehatSdk, EventStatus
from satusehat_sdk.errors import classify_http


def config(tmp_path):
    return SatusehatConfig(
        client_id="test-client", client_secret="test-secret", organization_id="10000001",
        queue_path=str(tmp_path / "q.db"), rate_limit_rpm=100000
    )


def test_classification():
    assert classify_http(200) == ("success", False)
    assert classify_http(429) == ("rate_limited", True)
    assert classify_http(503) == ("server_error", True)
    assert classify_http(422) == ("validation_error", False)


def test_enqueue_persists(tmp_path):
    sdk = SatusehatSdk(config(tmp_path))
    eid = sdk.enqueue("POST", "Encounter", payload={"resourceType":"Encounter"})
    row = sdk.queue.get(eid)
    assert row["status"] == EventStatus.QUEUED.value
    assert row["resource_type"] == "Encounter"
    sdk.close()


def test_put_requires_id(tmp_path):
    sdk = SatusehatSdk(config(tmp_path))
    try:
        sdk.enqueue("PUT", "Encounter", payload={"resourceType":"Encounter"})
        assert False
    except ValueError:
        pass
    finally:
        sdk.close()


def test_worker_success(tmp_path):
    sdk = SatusehatSdk(config(tmp_path))
    eid = sdk.enqueue("POST", "Encounter", payload={"resourceType": "Encounter"})
    sdk.fhir.request_once = lambda *args, **kwargs: __import__('satusehat_sdk').FhirResponse(201, '{"id":"abc"}', {})
    assert sdk.process_once(10) == 1
    assert sdk.queue.get(eid)["status"] == "SUCCESS"
    sdk.close()


def test_worker_validation_error(tmp_path):
    sdk = SatusehatSdk(config(tmp_path))
    eid = sdk.enqueue("POST", "Encounter", payload={"resourceType": "Encounter"})
    sdk.fhir.request_once = lambda *args, **kwargs: __import__('satusehat_sdk').FhirResponse(422, 'bad data', {})
    sdk.process_once(10)
    row = sdk.queue.get(eid)
    assert row["status"] == "WAITING_FOR_CORRECTION"
    assert row["error_category"] == "validation_error"
    sdk.close()


def test_worker_rate_limit(tmp_path):
    sdk = SatusehatSdk(config(tmp_path))
    eid = sdk.enqueue("POST", "Encounter", payload={"resourceType": "Encounter"})
    sdk.fhir.request_once = lambda *args, **kwargs: __import__('satusehat_sdk').FhirResponse(429, 'slow down', {'Retry-After':'1'})
    sdk.process_once(10)
    row = sdk.queue.get(eid)
    assert row["status"] == "RATE_LIMITED"
    assert row["next_retry_at"] is not None
    sdk.close()

# Python SDK

Python 3.10+ reference implementation. Runtime uses only the Python standard library.

```bash
pip install -e '.[dev]'
pytest
```

```python
from satusehat_sdk import SatusehatConfig, SatusehatSdk

sdk = SatusehatSdk(SatusehatConfig.from_env())
event_id = sdk.enqueue("POST", "Encounter", payload={"resourceType": "Encounter", "status": "finished"})
processed = sdk.process_once(20)
sdk.close()
```

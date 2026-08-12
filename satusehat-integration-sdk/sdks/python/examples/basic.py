import json
from pathlib import Path
from satusehat_sdk import SatusehatConfig, SatusehatSdk
cfg=SatusehatConfig.from_env()
sdk=SatusehatSdk(cfg)
sample = Path(__file__).resolve().parents[3] / 'examples' / 'fhir' / 'encounter.json'
with sample.open('r', encoding='utf-8') as f:
    payload=json.load(f)
eid=sdk.enqueue('POST','Encounter',payload=payload)
print('queued',eid)
print('processed',sdk.process_once(20))
sdk.close()

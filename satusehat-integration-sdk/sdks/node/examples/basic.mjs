import {readFileSync} from 'node:fs';
import {SatusehatConfig,SatusehatSdk} from '../src/index.js';
const sdk=new SatusehatSdk(SatusehatConfig.fromEnv());
const encounter=JSON.parse(readFileSync(new URL('../../../examples/fhir/encounter.json', import.meta.url),'utf8'));
const id=sdk.enqueue('POST','Encounter',undefined,encounter);
console.log('queued',id);
console.log('processed',await sdk.processOnce(20));
sdk.close();

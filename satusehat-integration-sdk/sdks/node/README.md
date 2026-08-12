# Node.js / TypeScript SDK

Runtime target: Node.js 20+ using built-in `fetch` and the stable `better-sqlite3` package. TypeScript declarations are included.

```bash
npm test
npm run build
```

```js
import { SatusehatConfig, SatusehatSdk } from '@satusehat/integration-sdk';
const sdk = new SatusehatSdk(SatusehatConfig.fromEnv());
const eventId = sdk.enqueue('POST', 'Encounter', undefined, {resourceType:'Encounter'});
await sdk.processOnce(20);
sdk.close();
```

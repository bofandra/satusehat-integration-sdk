import { SQLiteQueue } from './queue.js';import { TokenProvider } from './auth.js';import { FhirClient } from './http.js';import { classifyHttp,EventStatus } from './errors.js';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
class RateLimiter{constructor(rpm){this.interval=60000/rpm;this.last=0;this.chain=Promise.resolve()}wait(){this.chain=this.chain.then(async()=>{const d=this.last+this.interval-Date.now();if(d>0)await sleep(d);this.last=Date.now()});return this.chain}}
export class SatusehatSdk{
 constructor(config){this.config=config;this.queue=new SQLiteQueue(config.queuePath,config.processingTimeoutSeconds);this.tokens=new TokenProvider(config);this.fhir=new FhirClient(config,this.tokens);this.rate=new RateLimiter(config.rateLimitRpm)}
 close(){this.queue.close()}
 enqueue(op,rt,id,payload,idempotencyKey){return this.queue.enqueue(this.config.organizationId,op,rt,id,payload,idempotencyKey)}
 queueStats(){return this.queue.stats()}
 deadLetters(limit=50){return this.queue.deadLetters(limit)}
 requeue(eventId){return this.queue.requeue(eventId)}
 async request(op,rt,id,payload){let last;for(let a=1;a<=this.config.maxRetries;a++){await this.rate.wait();try{last=await this.fhir.requestOnce(op,rt,id,payload)}catch(e){if(a>=this.config.maxRetries)throw e;await sleep(this.backoff(a));continue}if(last.statusCode===401)this.tokens.invalidate();const[,retry]=classifyHttp(last.statusCode);if(!retry||a>=this.config.maxRetries)return last;await sleep(this.backoff(a,last.headers['retry-after']))}return last}
 async processOnce(limit=20){const rows=this.queue.ready(limit);for(const row of rows){const attempt=this.queue.markProcessing(row.event_id);await this.rate.wait();let response;try{response=await this.fhir.requestOnce(row.operation,row.resource_type,row.resource_id,row.payload_json?JSON.parse(row.payload_json):undefined)}catch(e){this.schedule(row.event_id,attempt,'transport_error',e.message,null,null,EventStatus.RETRYING);continue}this.apply(row.event_id,attempt,response)}return rows.length}
 apply(id,a,r){const [cat,retry]=classifyHttp(r.statusCode);if(r.statusCode>=200&&r.statusCode<=299){this.queue.complete(id,EventStatus.SUCCESS,r.statusCode);return}if(r.statusCode===401)this.tokens.invalidate();if(retry){this.schedule(id,a,cat,r.body,r.statusCode,r.headers['retry-after'],r.statusCode===429?EventStatus.RATE_LIMITED:EventStatus.RETRYING);return}this.queue.complete(id,EventStatus.WAITING_FOR_CORRECTION,r.statusCode,cat,r.body)}
 schedule(id,a,cat,msg,httpStatus,retryAfter,target){if(a>=this.config.maxRetries){this.queue.complete(id,EventStatus.DEAD_LETTER,httpStatus,cat,msg);return}const next=new Date(Date.now()+this.backoff(a,retryAfter)).toISOString();this.queue.complete(id,target,httpStatus,cat,msg,next)}
 backoff(a,retryAfter){const n=Number(retryAfter);if(retryAfter!=null&&Number.isFinite(n)&&n>=0)return n*1000;const base=Math.min(this.config.maxBackoffMs,this.config.initialBackoffMs*2**Math.max(0,a-1));return base+Math.random()*Math.min(1000,base*.2)}
}

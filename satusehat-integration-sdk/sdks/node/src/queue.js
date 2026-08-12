import Database from 'better-sqlite3';
import { randomUUID } from 'node:crypto';
import { EventStatus } from './errors.js';
const ddl=`CREATE TABLE IF NOT EXISTS integration_events(event_id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,operation TEXT NOT NULL,resource_type TEXT NOT NULL,resource_id TEXT,payload_json TEXT,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT);CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at);`;
const now=()=>new Date().toISOString();
export class SQLiteQueue{
 constructor(path){this.db=new Database(path);this.db.pragma('journal_mode = WAL');this.db.exec(ddl)}
 close(){this.db.close()}
 enqueue(org,operation,rt,id,payload){const op=operation.toUpperCase();if(!['GET','POST','PUT','PATCH'].includes(op))throw new Error('unsupported operation');if(['PUT','PATCH'].includes(op)&&!id)throw new Error('resourceId required for PUT/PATCH');const eid=randomUUID(),n=now();this.db.prepare(`INSERT INTO integration_events(event_id,organization_id,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at)VALUES(?,?,?,?,?,?,?,0,?,?)`).run(eid,org,op,rt,id??null,payload==null?null:JSON.stringify(payload),EventStatus.QUEUED,n,n);return eid}
 ready(limit){return this.db.prepare(`SELECT * FROM integration_events WHERE status IN ('QUEUED','RETRYING','RATE_LIMITED') AND (next_retry_at IS NULL OR next_retry_at<=?) ORDER BY created_at LIMIT ?`).all(now(),limit)}
 markProcessing(id){this.db.prepare(`UPDATE integration_events SET status='PROCESSING',attempt=attempt+1,updated_at=? WHERE event_id=?`).run(now(),id);return Number(this.db.prepare(`SELECT attempt FROM integration_events WHERE event_id=?`).get(id).attempt)}
 complete(id,status,httpStatus=null,category=null,message=null,nextRetryAt=null){this.db.prepare(`UPDATE integration_events SET status=?,http_status=?,error_category=?,error_message=?,updated_at=?,next_retry_at=? WHERE event_id=?`).run(status,httpStatus,category,message?String(message).slice(0,2000):null,now(),nextRetryAt,id)}
 get(id){return this.db.prepare(`SELECT * FROM integration_events WHERE event_id=?`).get(id)}
}

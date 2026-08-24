from __future__ import annotations
import hashlib, hmac, json, sqlite3, uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")

def parse_operation_outcome(raw: str | None) -> dict[str, Any]:
    if not raw:
        return {"message": None, "issues": []}
    try: data = json.loads(raw)
    except Exception: return {"message": raw[:500], "issues": []}
    issues=[]
    if isinstance(data,dict) and data.get("resourceType")=="OperationOutcome":
        for i in data.get("issue") or []:
            if not isinstance(i,dict): continue
            details=i.get("details") if isinstance(i.get("details"),dict) else {}
            fields=i.get("expression") or i.get("location") or []
            if isinstance(fields,str): fields=[fields]
            issues.append({"severity":i.get("severity"),"code":i.get("code"),"message":i.get("diagnostics") or details.get("text") or i.get("code"),"fields":fields})
    msg=next((i.get("message") for i in issues if i.get("message")),None)
    if not msg and isinstance(data,dict): msg=data.get("message") or data.get("error")
    return {"message":msg or raw[:500],"issues":issues}

class IntegrationStore:
    def __init__(self,path:str):
        Path(path).parent.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(path,timeout=30,check_same_thread=False)
        self.db.row_factory=sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA busy_timeout=30000")
        self.migrate()
    def close(self): self.db.close()
    def migrate(self):
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS integration_events(event_id TEXT PRIMARY KEY,organization_id TEXT NOT NULL,idempotency_key TEXT,operation TEXT NOT NULL,resource_type TEXT NOT NULL,resource_id TEXT,payload_json TEXT,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT);
        CREATE INDEX IF NOT EXISTS idx_integration_events_ready ON integration_events(status,next_retry_at,created_at);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_events_idempotency ON integration_events(organization_id,idempotency_key) WHERE idempotency_key IS NOT NULL;
        """)
        cols={r["name"] for r in self.db.execute("PRAGMA table_info(integration_events)")}
        for name,typ in {"correlation_id":"TEXT","parent_event_id":"TEXT","revision":"INTEGER NOT NULL DEFAULT 1","source_system":"TEXT","source_record_id":"TEXT","disposition":"TEXT","error_details_json":"TEXT","completed_at":"TEXT","superseded_by_event_id":"TEXT"}.items():
            if name not in cols: self.db.execute(f"ALTER TABLE integration_events ADD COLUMN {name} {typ}")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS integration_event_history(history_id TEXT PRIMARY KEY,event_id TEXT NOT NULL,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_category TEXT,error_message TEXT,observed_updated_at TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(event_id,status,attempt,observed_updated_at));
        CREATE INDEX IF NOT EXISTS idx_event_history_event ON integration_event_history(event_id,created_at);
        CREATE TABLE IF NOT EXISTS integration_notifications(notification_id TEXT PRIMARY KEY,event_id TEXT NOT NULL,event_type TEXT NOT NULL,destination TEXT,payload_json TEXT NOT NULL,status TEXT NOT NULL,attempt INTEGER NOT NULL DEFAULT 0,http_status INTEGER,error_message TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,next_retry_at TEXT,delivered_at TEXT,UNIQUE(event_id,event_type));
        CREATE INDEX IF NOT EXISTS idx_notifications_ready ON integration_notifications(status,next_retry_at,created_at);
        """)
        self.db.execute("UPDATE integration_events SET correlation_id=event_id WHERE correlation_id IS NULL OR correlation_id='' ")
        self.db.execute("UPDATE integration_events SET revision=1 WHERE revision IS NULL OR revision<1")
        self.db.commit()
    def synchronize(self,webhook_url:str|None,enabled:set[str]):
        rows=self.db.execute("SELECT * FROM integration_events ORDER BY updated_at DESC LIMIT 5000").fetchall(); now=utcnow()
        with self.db:
            for r in rows:
                self.db.execute("INSERT OR IGNORE INTO integration_event_history(history_id,event_id,status,attempt,http_status,error_category,error_message,observed_updated_at,created_at) VALUES(?,?,?,?,?,?,?,?,?)",(str(uuid.uuid4()),r["event_id"],r["status"],int(r["attempt"] or 0),r["http_status"],r["error_category"],r["error_message"],r["updated_at"],now))
                details=parse_operation_outcome(r["error_message"])
                if r["error_message"] and not r["error_details_json"]:
                    self.db.execute("UPDATE integration_events SET error_details_json=? WHERE event_id=?",(json.dumps(details,separators=(",",":")),r["event_id"]))
                event_type=None
                if r["status"]=="WAITING_FOR_CORRECTION" and not r["superseded_by_event_id"]:
                    hs=r["http_status"]
                    if hs in (400,422): disp="CORRECT_DATA"; event_type="integration.correction_required"
                    elif hs==404: disp="REVIEW_REFERENCE"; event_type="integration.correction_required"
                    elif hs in (401,403): disp="FIX_CONFIGURATION"
                    elif hs==409: disp="REVIEW_CONFLICT"
                    else: disp="REVIEW"
                    self.db.execute("UPDATE integration_events SET disposition=? WHERE event_id=?",(disp,r["event_id"]))
                elif r["status"]=="DEAD_LETTER": event_type="integration.dead_letter"
                elif r["status"]=="SUCCESS": event_type="integration.delivery_succeeded"
                if event_type and event_type in enabled:
                    payload={"schema_version":"1.0","type":event_type,"event_id":r["event_id"],"correlation_id":r["correlation_id"] or r["event_id"],"revision":int(r["revision"] or 1),"organization_id":r["organization_id"],"source_system":r["source_system"],"source_record_id":r["source_record_id"],"idempotency_key":r["idempotency_key"],"resource_type":r["resource_type"],"resource_id":r["resource_id"],"operation":r["operation"],"status":r["status"],"http_status":r["http_status"],"error":{"category":r["error_category"],"message":details.get("message"),"issues":details.get("issues",[])},"occurred_at":r["updated_at"]}
                    self.db.execute("INSERT OR IGNORE INTO integration_notifications(notification_id,event_id,event_type,destination,payload_json,status,attempt,created_at,updated_at) VALUES(?,?,?,?,?,'PENDING',0,?,?)",(str(uuid.uuid4()),r["event_id"],event_type,webhook_url,json.dumps(payload,separators=(",",":")),now,now))
    def summary(self):
        counts={r["status"]:int(r["n"]) for r in self.db.execute("SELECT status,COUNT(*) n FROM integration_events WHERE superseded_by_event_id IS NULL GROUP BY status")}
        total=sum(counts.values()); success=counts.get("SUCCESS",0); q=sum(counts.get(s,0) for s in ("QUEUED","PROCESSING","RETRYING","RATE_LIMITED"))
        old=self.db.execute("SELECT created_at FROM integration_events WHERE superseded_by_event_id IS NULL AND status IN ('QUEUED','PROCESSING','RETRYING','RATE_LIMITED') ORDER BY created_at LIMIT 1").fetchone()
        notif={r["status"]:int(r["n"]) for r in self.db.execute("SELECT status,COUNT(*) n FROM integration_notifications GROUP BY status")}
        return {"counts":counts,"total":total,"success_rate":round(success/total*100 if total else 0,2),"queue_depth":q,"oldest_queued_at":old["created_at"] if old else None,"notifications":notif}
    def list_events(self,limit=100,status=None,corrections_only=False):
        w=["1=1"]; a=[]
        if status: w.append("status=?"); a.append(status)
        if corrections_only: w += ["status='WAITING_FOR_CORRECTION'","superseded_by_event_id IS NULL","COALESCE(disposition,'') IN ('CORRECT_DATA','REVIEW_REFERENCE')"]
        a.append(min(max(int(limit),1),500))
        rows=self.db.execute(f"SELECT event_id,correlation_id,parent_event_id,revision,organization_id,idempotency_key,source_system,source_record_id,operation,resource_type,resource_id,status,attempt,http_status,error_category,error_message,error_details_json,disposition,created_at,updated_at,next_retry_at,superseded_by_event_id FROM integration_events WHERE {' AND '.join(w)} ORDER BY updated_at DESC LIMIT ?",a).fetchall()
        out=[]
        for r in rows:
            d=dict(r)
            if d.get("error_details_json"):
                try:d["error_details"]=json.loads(d.pop("error_details_json"))
                except Exception:pass
            out.append(d)
        return out
    def get_event(self,eid):
        r=self.db.execute("SELECT * FROM integration_events WHERE event_id=?",(eid,)).fetchone()
        if not r:return None
        d=dict(r); d["payload_json"]=None
        if d.get("error_details_json"):
            try:d["error_details"]=json.loads(d["error_details_json"])
            except Exception:pass
        return d
    def history(self,eid): return [dict(r) for r in self.db.execute("SELECT * FROM integration_event_history WHERE event_id=? ORDER BY observed_updated_at,created_at",(eid,))]
    def notifications(self,limit=100): return [dict(r) for r in self.db.execute("SELECT notification_id,event_id,event_type,destination,status,attempt,http_status,error_message,created_at,updated_at,next_retry_at,delivered_at FROM integration_notifications ORDER BY updated_at DESC LIMIT ?",(min(max(int(limit),1),500),))]
    def ready_notifications(self,limit=20): return self.db.execute("SELECT * FROM integration_notifications WHERE status IN ('PENDING','RETRYING') AND (next_retry_at IS NULL OR next_retry_at<=?) ORDER BY created_at LIMIT ?",(utcnow(),limit)).fetchall()
    def update_notification(self,nid,*,status,attempt,http_status=None,error_message=None,next_retry_at=None,delivered_at=None):
        with self.db:self.db.execute("UPDATE integration_notifications SET status=?,attempt=?,http_status=?,error_message=?,updated_at=?,next_retry_at=?,delivered_at=? WHERE notification_id=?",(status,attempt,http_status,error_message[:1000] if error_message else None,utcnow(),next_retry_at,delivered_at,nid))
    def update_context(self,eid,*,correlation_id=None,source_system=None,source_record_id=None):
        r=self.db.execute("SELECT * FROM integration_events WHERE event_id=?",(eid,)).fetchone()
        if not r:raise KeyError("event not found")
        corr=(correlation_id or r["correlation_id"] or eid).strip(); ss=source_system if source_system is not None else r["source_system"]; sr=source_record_id if source_record_id is not None else r["source_record_id"]
        with self.db:self.db.execute("UPDATE integration_events SET correlation_id=?,source_system=?,source_record_id=? WHERE event_id=?",(corr,ss,sr,eid))
        return {"event_id":eid,"correlation_id":corr,"source_system":ss,"source_record_id":sr}
    def submit_correction(self,orig_id,payload,idempotency_key=None,resource_id=None):
        o=self.db.execute("SELECT * FROM integration_events WHERE event_id=?",(orig_id,)).fetchone()
        if not o:raise KeyError("event not found")
        if o["status"] not in ("WAITING_FOR_CORRECTION","DEAD_LETTER"):raise ValueError("only WAITING_FOR_CORRECTION or DEAD_LETTER events can be corrected")
        if o["superseded_by_event_id"]:
            e=self.db.execute("SELECT event_id,correlation_id,revision,status FROM integration_events WHERE event_id=?",(o["superseded_by_event_id"],)).fetchone(); return {**dict(e),"existing":True}
        if not isinstance(payload,dict) or not payload.get("resourceType"):raise ValueError("payload must be a FHIR resource object with resourceType")
        if payload.get("resourceType")!=o["resource_type"]:raise ValueError("corrected payload resourceType must match original resource_type")
        pj=json.dumps(payload,separators=(",",":")); corr=o["correlation_id"] or o["event_id"]; rev=int(o["revision"] or 1)+1
        key=idempotency_key or f"{o['idempotency_key'] or o['resource_type']+':'+corr}:correction:{rev}"
        e=self.db.execute("SELECT event_id,correlation_id,revision,status FROM integration_events WHERE organization_id=? AND idempotency_key=?",(o["organization_id"],key)).fetchone()
        if e:return {**dict(e),"existing":True}
        nid=str(uuid.uuid4()); n=utcnow()
        with self.db:
            self.db.execute("INSERT INTO integration_events(event_id,organization_id,idempotency_key,operation,resource_type,resource_id,payload_json,status,attempt,created_at,updated_at,correlation_id,parent_event_id,revision,source_system,source_record_id,disposition) VALUES(?,?,?,?,?,?,?,'QUEUED',0,?,?,?,?,?,?,?,?)",(nid,o["organization_id"],key,o["operation"],o["resource_type"],resource_id if resource_id is not None else o["resource_id"],pj,n,n,corr,orig_id,rev,o["source_system"],o["source_record_id"],"RETRY_CORRECTED_DATA"))
            self.db.execute("UPDATE integration_events SET superseded_by_event_id=?,disposition='SUPERSEDED_BY_CORRECTION' WHERE event_id=?",(nid,orig_id))
            self.db.execute("INSERT OR IGNORE INTO integration_event_history(history_id,event_id,status,attempt,observed_updated_at,created_at) VALUES(?,?,'QUEUED',0,?,?)",(str(uuid.uuid4()),nid,n,n))
        return {"event_id":nid,"correlation_id":corr,"revision":rev,"status":"QUEUED","existing":False}
    def requeue(self,eid):
        r=self.db.execute("SELECT superseded_by_event_id FROM integration_events WHERE event_id=?",(eid,)).fetchone()
        if not r or r["superseded_by_event_id"]:return False
        with self.db:c=self.db.execute("UPDATE integration_events SET status='QUEUED',attempt=0,http_status=NULL,error_category=NULL,error_message=NULL,error_details_json=NULL,updated_at=?,next_retry_at=NULL,disposition=NULL WHERE event_id=? AND status IN ('DEAD_LETTER','WAITING_FOR_CORRECTION','CANCELLED')",(utcnow(),eid))
        return c.rowcount>0

def signature(secret,timestamp,body:bytes):
    return "v1="+hmac.new(secret.encode(),timestamp.encode()+b"."+body,hashlib.sha256).hexdigest()

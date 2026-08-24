#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,os,threading,time,urllib.error,urllib.request
from datetime import datetime,timedelta,timezone
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs,urlparse
from store import IntegrationStore,signature,utcnow
ROOT=Path(__file__).resolve().parent; STATIC=ROOT/"static"
class App:
    def __init__(self):
        self.queue_path=os.getenv("SATUSEHAT_QUEUE_PATH","./satusehat-sdk.db"); self.webhook_url=os.getenv("SATUSEHAT_WEBHOOK_URL") or None; self.webhook_secret=os.getenv("SATUSEHAT_WEBHOOK_SECRET",""); self.api_token=os.getenv("SATUSEHAT_CONSOLE_API_TOKEN",""); self.max_retries=int(os.getenv("SATUSEHAT_WEBHOOK_MAX_RETRIES","8")); self.timeout=int(os.getenv("SATUSEHAT_WEBHOOK_TIMEOUT_SECONDS","10")); aliases={"correction_required":"integration.correction_required","dead_letter":"integration.dead_letter","delivery_succeeded":"integration.delivery_succeeded"}; self.enabled={aliases.get(x.strip(),x.strip()) for x in os.getenv("SATUSEHAT_WEBHOOK_EVENTS","correction_required,dead_letter").split(",") if x.strip()}; self.store=IntegrationStore(self.queue_path); self.stop=threading.Event()
    def start(self): threading.Thread(target=self.loop,daemon=True,name="integration-console-worker").start()
    def loop(self):
        while not self.stop.wait(1):
            try:self.store.synchronize(self.webhook_url,self.enabled); self.process_notifications_once()
            except Exception as e:print("[console-worker]",type(e).__name__,e,flush=True)
    def process_notifications_once(self):
        if not self.webhook_url:return 0
        rows=self.store.ready_notifications(20)
        for r in rows:
            a=int(r["attempt"] or 0)+1; body=r["payload_json"].encode(); ts=str(int(time.time())); h={"Content-Type":"application/json","User-Agent":"satusehat-integration-sdk-console/0.2.0","X-SSSDK-Event":r["event_type"],"X-SSSDK-Delivery":r["notification_id"],"X-SSSDK-Timestamp":ts}
            if self.webhook_secret:h["X-SSSDK-Signature"]=signature(self.webhook_secret,ts,body)
            req=urllib.request.Request(self.webhook_url,data=body,headers=h,method="POST")
            try:
                with urllib.request.urlopen(req,timeout=self.timeout) as resp:
                    code=int(resp.status)
                    if 200<=code<300:self.store.update_notification(r["notification_id"],status="DELIVERED",attempt=a,http_status=code,delivered_at=utcnow())
                    else:self.fail(r["notification_id"],a,code,f"HTTP {code}")
            except urllib.error.HTTPError as e:self.fail(r["notification_id"],a,int(e.code),f"HTTP {e.code}: {e.reason}")
            except Exception as e:self.fail(r["notification_id"],a,None,str(e))
        return len(rows)
    def fail(self,nid,a,hs,msg):
        retry=hs is None or hs in (408,429) or 500<=hs<=599
        if retry and a<self.max_retries:
            nxt=(datetime.now(timezone.utc)+timedelta(seconds=min(3600,60*2**max(0,a-1)))).isoformat().replace("+00:00","Z"); self.store.update_notification(nid,status="RETRYING",attempt=a,http_status=hs,error_message=msg,next_retry_at=nxt)
        else:self.store.update_notification(nid,status="DEAD_LETTER",attempt=a,http_status=hs,error_message=msg)
APP=None
class H(BaseHTTPRequestHandler):
    server_version="SatusehatIntegrationConsole/0.2.0"
    def log_message(self,fmt,*args):print("[console] "+fmt%args,flush=True)
    def js(self,status,obj):
        b=json.dumps(obj,ensure_ascii=False,default=str).encode(); self.send_response(status); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Cache-Control","no-store"); self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b)
    def body(self):
        n=int(self.headers.get("Content-Length","0"));
        if n>5*1024*1024:raise ValueError("request body too large")
        return json.loads(self.rfile.read(n) or b"{}")
    def auth(self):return (self.headers.get("Authorization")==f"Bearer {APP.api_token}") if APP.api_token else self.client_address[0] in ("127.0.0.1","::1")
    def static(self,name,ct):
        p=STATIC/name
        if not p.exists():return self.js(404,{"error":"asset_not_found"})
        b=p.read_bytes(); self.send_response(200); self.send_header("Content-Type",ct); self.send_header("Cache-Control","no-store"); self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u=urlparse(self.path)
        if u.path=="/healthz":return self.js(200,{"status":"ok","queue_path":APP.queue_path})
        if u.path=="/api/v1/summary":APP.store.synchronize(APP.webhook_url,APP.enabled); return self.js(200,APP.store.summary())
        if u.path=="/api/v1/events":
            q=parse_qs(u.query); return self.js(200,APP.store.list_events(int(q.get("limit",[100])[0]),q.get("status",[None])[0]))
        if u.path=="/api/v1/corrections":APP.store.synchronize(APP.webhook_url,APP.enabled); return self.js(200,APP.store.list_events(200,corrections_only=True))
        if u.path=="/api/v1/notifications":return self.js(200,APP.store.notifications(200))
        if u.path.startswith("/api/v1/events/"):
            p=u.path.strip("/").split("/")
            if len(p)==5 and p[4]=="history":return self.js(200,APP.store.history(p[3]))
            if len(p)==4:
                e=APP.store.get_event(p[3]); return self.js(200 if e else 404,e or {"error":"not_found"})
        if u.path in ("/","/index.html"):return self.static("index.html","text/html; charset=utf-8")
        if u.path=="/app.js":return self.static("app.js","text/javascript; charset=utf-8")
        if u.path=="/styles.css":return self.static("styles.css","text/css; charset=utf-8")
        return self.js(404,{"error":"not_found"})
    def do_POST(self):
        if not self.auth():return self.js(401,{"error":"unauthorized"})
        p=urlparse(self.path).path.strip("/").split("/")
        try:
            d=self.body()
            if len(p)==5 and p[:3]==["api","v1","events"] and p[4]=="corrections":return self.js(202,APP.store.submit_correction(p[3],d.get("payload"),d.get("idempotency_key"),d.get("resource_id")))
            if len(p)==5 and p[:3]==["api","v1","events"] and p[4]=="context":return self.js(200,APP.store.update_context(p[3],correlation_id=d.get("correlation_id"),source_system=d.get("source_system"),source_record_id=d.get("source_record_id")))
            if len(p)==5 and p[:3]==["api","v1","events"] and p[4]=="requeue":
                ok=APP.store.requeue(p[3]); return self.js(200 if ok else 409,{"requeued":ok})
        except KeyError as e:return self.js(404,{"error":str(e)})
        except ValueError as e:return self.js(422,{"error":str(e)})
        except Exception as e:return self.js(500,{"error":type(e).__name__,"message":str(e)})
        return self.js(404,{"error":"not_found"})
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--host",default=os.getenv("SATUSEHAT_CONSOLE_HOST","127.0.0.1")); ap.add_argument("--port",type=int,default=int(os.getenv("SATUSEHAT_CONSOLE_PORT","8787"))); a=ap.parse_args(); global APP; APP=App(); APP.store.synchronize(APP.webhook_url,APP.enabled); APP.start(); srv=ThreadingHTTPServer((a.host,a.port),H); print(f"SATUSEHAT Integration Console: http://{a.host}:{a.port}"); print("Queue DB:",APP.queue_path); print("Webhook:","enabled" if APP.webhook_url else "not configured")
    try:srv.serve_forever()
    except KeyboardInterrupt:pass
    finally:APP.stop.set();srv.server_close();APP.store.close()
if __name__=="__main__":main()

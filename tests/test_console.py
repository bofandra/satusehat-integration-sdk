import json,os,sys,tempfile,threading,unittest
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'services'/'console'))
from store import IntegrationStore,signature
from server import App
class T(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.path=str(Path(self.tmp.name)/'q.db');self.s=IntegrationStore(self.path)
    def tearDown(self):self.s.close();self.tmp.cleanup()
    def bad(self):
        n='2026-08-23T10:00:00.000Z';oo={"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"invalid","diagnostics":"Patient reference is invalid","expression":["Encounter.subject.reference"]}]};self.s.db.execute("INSERT INTO integration_events(event_id,organization_id,idempotency_key,operation,resource_type,payload_json,status,attempt,http_status,error_category,error_message,created_at,updated_at,correlation_id,revision,source_system,source_record_id) VALUES('evt-1','org-1','enc:123','POST','Encounter','{}','WAITING_FOR_CORRECTION',1,400,'invalid_request',?,?,?,'visit-123',1,'SIMRS-TEST','ENC-123')",(json.dumps(oo),n,n));self.s.db.commit()
    def test_sync(self):
        self.bad();self.s.synchronize('http://client.invalid/hook',{'integration.correction_required'});self.assertEqual(1,len(self.s.notifications()));e=self.s.get_event('evt-1');self.assertEqual('Patient reference is invalid',e['error_details']['message']);self.assertEqual('CORRECT_DATA',e['disposition'])
    def test_correction_revision(self):
        self.bad();r=self.s.submit_correction('evt-1',{'resourceType':'Encounter','status':'finished'});self.assertEqual(2,r['revision']);n=self.s.db.execute('select * from integration_events where event_id=?',(r['event_id'],)).fetchone();self.assertEqual('evt-1',n['parent_event_id']);self.assertEqual('QUEUED',n['status']);self.assertEqual([],self.s.list_events(corrections_only=True))
    def test_duplicate_correction(self):
        self.bad();a=self.s.submit_correction('evt-1',{'resourceType':'Encounter'},'fixed:2');b=self.s.submit_correction('evt-1',{'resourceType':'Encounter'},'fixed:2');self.assertEqual(a['event_id'],b['event_id']);self.assertTrue(b['existing'])
    def test_context(self):
        self.bad();r=self.s.update_context('evt-1',correlation_id='visit-new',source_system='SIMRS',source_record_id='R-1');self.assertEqual('visit-new',r['correlation_id']);self.assertEqual('R-1',r['source_record_id'])
    def test_webhook(self):
        recv={};secret='secret'
        class H(BaseHTTPRequestHandler):
            def log_message(self,*a):pass
            def do_POST(self):
                b=self.rfile.read(int(self.headers.get('Content-Length','0')));recv.update(body=b,ts=self.headers.get('X-SSSDK-Timestamp'),sig=self.headers.get('X-SSSDK-Signature'));self.send_response(204);self.end_headers()
        srv=HTTPServer(('127.0.0.1',0),H);threading.Thread(target=srv.serve_forever,daemon=True).start();old=dict(os.environ)
        try:
            os.environ.update(SATUSEHAT_QUEUE_PATH=self.path,SATUSEHAT_WEBHOOK_URL=f'http://127.0.0.1:{srv.server_port}/hook',SATUSEHAT_WEBHOOK_SECRET=secret,SATUSEHAT_WEBHOOK_EVENTS='correction_required');self.bad();app=App();app.store.synchronize(app.webhook_url,app.enabled);self.assertEqual(1,app.process_notifications_once());self.assertEqual('DELIVERED',app.store.notifications()[0]['status']);self.assertEqual(signature(secret,recv['ts'],recv['body']),recv['sig']);body=json.loads(recv['body']);self.assertEqual('ENC-123',body['source_record_id']);self.assertNotIn('payload_json',body);app.store.close()
        finally:os.environ.clear();os.environ.update(old);srv.shutdown();srv.server_close()
if __name__=='__main__':unittest.main()

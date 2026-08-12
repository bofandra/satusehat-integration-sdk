#!/usr/bin/env python3
"""Tiny local SATUSEHAT-like mock for SDK development only."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, os, time, uuid

PORT=int(os.environ.get('MOCK_PORT','8765'))
class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): print('[mock]', fmt % args)
    def send_json(self,status,obj,headers=None):
        body=json.dumps(obj).encode();self.send_response(status);self.send_header('Content-Type','application/json');
        for k,v in (headers or {}).items():self.send_header(k,v)
        self.end_headers();self.wfile.write(body)
    def do_POST(self):
        if self.path.startswith('/oauth2/v1/accesstoken'):
            self.send_json(200,{'access_token':'mock-access-token','token_type':'BearerToken','expires_in':'3599','issued_at':str(int(time.time()*1000))});return
        if self.path.startswith('/fhir-r4/v1/'):
            n=int(self.headers.get('Content-Length','0'));raw=self.rfile.read(n) if n else b'{}'
            try: obj=json.loads(raw or b'{}')
            except Exception: self.send_json(400,{'resourceType':'OperationOutcome','issue':[{'severity':'error','code':'invalid','details':{'text':'invalid JSON'}}]});return
            if self.headers.get('X-Mock-Status'):
                s=int(self.headers['X-Mock-Status']);self.send_json(s,{'resourceType':'OperationOutcome','issue':[{'severity':'error','code':'processing','details':{'text':'forced mock status'}}]}, {'Retry-After':'1'} if s==429 else None);return
            obj.setdefault('id',str(uuid.uuid4()));self.send_json(201,obj);return
        self.send_json(404,{'error':'not found'})
    def do_PUT(self): self.do_POST()
    def do_PATCH(self): self.do_POST()
    def do_GET(self):
        if self.path.startswith('/fhir-r4/v1/'):
            rt=self.path.split('/')[3] if len(self.path.split('/'))>3 else 'Bundle'
            self.send_json(200,{'resourceType':rt,'id':'mock-id'});return
        self.send_json(404,{'error':'not found'})

print(f'Mock SATUSEHAT listening on http://127.0.0.1:{PORT}')
ThreadingHTTPServer(('127.0.0.1',PORT),H).serve_forever()

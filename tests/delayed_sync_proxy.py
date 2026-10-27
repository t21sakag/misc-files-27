"""Loopback-only delay fixture for simulator background-sync checks."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from sync_proxy_body import read_body
import sys
import time
import urllib.request

upstream = 'http://127.0.0.1:18891'

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = read_body(self)
        request = urllib.request.Request(upstream + self.path, data=body,
            headers={k: v for k, v in self.headers.items() if k.lower() not in ('host', 'connection', 'content-length', 'transfer-encoding')})
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
            self.send_response(response.status)
            for key, value in response.headers.items():
                if key.lower() not in ('content-length', 'connection', 'transfer-encoding'):
                    self.send_header(key, value)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try:
                if self.path.rstrip('/').endswith('/download'):
                    self.wfile.write(data[:1]); self.wfile.flush()
                    print('download response paused', flush=True)
                    time.sleep(12)
                    self.wfile.write(data[1:])
                else:
                    self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                print('download client disconnected', flush=True)
    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 18893), Handler)
server.daemon_threads = True
print('delayed loopback fixture ready', flush=True)
server.serve_forever()

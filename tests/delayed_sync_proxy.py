"""Loopback-only delay fixture for simulator background-sync checks."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
from sync_proxy_body import read_body
import argparse
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

class LoopbackHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # HTTPServer normally reverse-resolves its address during construction.
        # This synthetic loopback service needs no DNS/network name discovery.
        TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]


def main():
    global upstream
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18893)
    parser.add_argument('--upstream-port', type=int, default=18891)
    args = parser.parse_args()
    assert 1024 <= args.port <= 65535 and 1024 <= args.upstream_port <= 65535
    upstream = f'http://127.0.0.1:{args.upstream_port}'
    server = LoopbackHTTPServer(('127.0.0.1', args.port), Handler)
    print('delayed loopback fixture ready', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()

"""Interrupt a real full download mid-response, reopen, and safely retry it."""
from engine_smoke import Engine, lib, unpack
from sync_proxy_body import read_body
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    endpoint = f'http://127.0.0.1:{free_port()}/'
    env = os.environ | {'SYNC_USER1': 'fixture:fixture-password', 'SYNC_HOST': '127.0.0.1',
                        'SYNC_PORT': endpoint.split(':')[-1].strip('/'), 'SYNC_BASE': str(root / 'server')}
    with (root / 'server.log').open('w') as log:
        server = subprocess.Popen([str(Path(sys.argv[2]).resolve())], env=env, stdout=log, stderr=log)
        release = threading.Event()
        started = threading.Event()
        gate = threading.Event()
        class Proxy(BaseHTTPRequestHandler):
            def do_POST(self):
                payload = read_body(self)
                request = urllib.request.Request(endpoint.rstrip('/') + self.path, data=payload,
                    headers={k: v for k, v in self.headers.items() if k.lower() not in ('host', 'connection', 'content-length', 'transfer-encoding')})
                with urllib.request.urlopen(request, timeout=20) as response:
                    body = response.read()
                    self.send_response(response.status)
                    for key, value in response.headers.items():
                        if key.lower() not in ('content-length', 'connection', 'transfer-encoding'):
                            self.send_header(key, value)
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    try:
                        if self.path.rstrip('/').endswith('/download') and gate.is_set():
                            self.wfile.write(body[:1]); self.wfile.flush()
                            started.set()
                            assert release.wait(20), 'Interrupted response was not released'
                            self.wfile.write(body[1:])
                        else:
                            self.wfile.write(body)
                    except (BrokenPipeError, ConnectionResetError):
                        pass
            def log_message(self, *_):
                pass
        proxy = ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
        proxy.daemon_threads = True
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
        try:
            deadline = time.monotonic() + 30
            while True:
                try:
                    urllib.request.urlopen(endpoint + 'health', timeout=1).close(); break
                except OSError:
                    assert server.poll() is None and time.monotonic() < deadline
                    time.sleep(.1)
            source = Engine(root / 'source')
            note = source.call('NotesService.NewNote', {'ntid': source.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']})
            note['fields'] = ['Server card survives interruption', 'Remote answer']
            remote_id = source.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
            auth = source.call('SyncService.SyncLogin', {'username': 'fixture', 'password': 'fixture-password', 'endpoint': endpoint})
            decision = source.call('SyncService.SyncCollection', {'auth': auth, 'syncMedia': False})
            source.call('SyncService.FullUploadOrDownload', {'auth': auth, 'upload': True, 'serverUsn': decision.get('serverMediaUsn', 0)})
            source.close()
            target = Engine(root / 'target')
            local = target.call('NotesService.NewNote', {'ntid': target.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']})
            local['fields'] = ['Local sentinel before download', 'Must survive cancellation']
            local_id = target.call('NotesService.AddNote', {'note': local, 'deckId': '1'})['noteId']
            proxied_auth = dict(auth, endpoint=f'http://127.0.0.1:{proxy.server_port}/')
            decision = target.call('SyncService.SyncCollection', {'auth': proxied_auth, 'syncMedia': False})
            assert decision['required'] == 'FULL_SYNC', decision
            args = {'auth': proxied_auth, 'upload': False, 'serverUsn': decision.get('serverMediaUsn', 0)}
            gate.set()
            with ThreadPoolExecutor(max_workers=1) as executor:
                download = executor.submit(lambda: unpack(lib.ap_call(target.handle, b'SyncService.FullUploadOrDownload', json.dumps(args).encode())))
                assert started.wait(20), 'Full download never reached the response gate'
                target.call('SyncService.AbortSync')
                result = download.result(timeout=15)
                assert 'error' in result, result
                gate.clear(); release.set()
            assert target.call('NotesService.GetNote', {'nid': local_id})['fields'] == local['fields']
            target.close()
            target = Engine(root / 'target')
            assert target.call('NotesService.GetNote', {'nid': local_id})['fields'] == local['fields']
            decision = target.call('SyncService.SyncCollection', {'auth': proxied_auth, 'syncMedia': False})
            args['serverUsn'] = decision.get('serverMediaUsn', 0)
            target.call('SyncService.FullUploadOrDownload', args)
            deadline = time.monotonic() + 30
            while target.call('SyncService.MediaSyncStatus').get('active'):
                assert time.monotonic() < deadline
                time.sleep(.1)
            assert target.call('NotesService.GetNote', {'nid': remote_id})['fields'] == note['fields']
            target.close()
            print('PASS: mid-download abort, original collection preserved, reopen, full retry and media completion')
        finally:
            release.set()
            proxy.shutdown(); proxy.server_close()
            server.terminate(); server.wait(timeout=10)

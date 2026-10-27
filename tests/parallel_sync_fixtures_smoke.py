"""Run two real sync servers/proxies concurrently and prove mutations stay isolated."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from engine_smoke import Engine

bridge, binary, fixture = map(lambda value: str(Path(value).resolve()), sys.argv[1:4])
scripts = Path(__file__).resolve().parent

def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]

with tempfile.TemporaryDirectory(prefix='parallel-sync-fixtures-') as temporary:
    root = Path(temporary)
    processes = []
    streams = []
    clients = []
    ports = set()
    def unique_port():
        while True:
            value = port()
            if value not in ports:
                ports.add(value)
                return value
    try:
        endpoints = []
        logs = []
        for group in ('manual', 'automatic'):
            upstream, proxy = unique_port(), unique_port()
            log = (root / (group + '-server.log')).open('w'); streams.append(log)
            env = os.environ | {'SYNC_USER1': 'fixture@example.test:fixture-password',
                'SYNC_USER2': 'empty@example.test:fixture-password', 'SYNC_HOST': '127.0.0.1',
                'SYNC_PORT': str(upstream), 'SYNC_BASE': str(root / group)}
            server = subprocess.Popen([binary], env=env, stdout=log, stderr=log)
            processes.append(server)
            deadline = time.monotonic() + 120
            while True:
                assert server.poll() is None, (root / (group + '-server.log')).read_text()
                try:
                    urllib.request.urlopen(f'http://127.0.0.1:{upstream}/health', timeout=1).close()
                    break
                except OSError as error:
                    assert time.monotonic() < deadline, (str(error), (root / (group + '-server.log')).read_text())
                    time.sleep(.1)
            subprocess.run([sys.executable, str(scripts / 'seed_ui_sync.py'), bridge, fixture, str(upstream)], check=True)
            proxy_log = root / (group + '-proxy.log')
            log = proxy_log.open('w'); streams.append(log); logs.append(proxy_log)
            child = subprocess.Popen([sys.executable, str(scripts / 'delayed_sync_proxy.py'), '--port', str(proxy),
                '--upstream-port', str(upstream)], stdout=log, stderr=log)
            processes.append(child)
            deadline = time.monotonic() + 10
            while True:
                assert child.poll() is None, proxy_log.read_text()
                try:
                    with socket.create_connection(('127.0.0.1', proxy), timeout=1): break
                except OSError:
                    assert time.monotonic() < deadline, 'Proxy failed to listen'
                    time.sleep(.05)
            endpoints.append(f'http://127.0.0.1:{proxy}/')
        def download(index):
            engine = Engine(root / ('client-' + str(index))); clients.append(engine)
            auth = engine.call('SyncService.SyncLogin', {'username': 'fixture@example.test',
                'password': 'fixture-password', 'endpoint': endpoints[index]})
            decision = engine.call('SyncService.SyncCollection', {'auth': auth, 'syncMedia': False})
            assert decision['required'] == 'FULL_DOWNLOAD', decision
            engine.call('SyncService.FullUploadOrDownload', {'auth': auth, 'upload': False,
                'serverUsn': decision.get('serverMediaUsn', 0)})
            return engine, auth
        with ThreadPoolExecutor(max_workers=2) as workers:
            pairs = list(workers.map(download, range(2)))
        for log in logs:
            assert 'download response paused' in log.read_text(), 'A proxy routed to the wrong server'
        (a, auth_a), (b, auth_b) = pairs
        before_b = b.call('SearchService.SearchCards', {'search': ''})['ids']
        note = a.call('NotesService.NewNote', {'ntid': a.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']})
        note['fields'] = ['Only group A', 'Independent server storage']
        a.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
        for engine, auth in ((a, auth_a), (b, auth_b)):
            outcome = engine.call('SyncService.SyncCollection', {'auth': auth, 'syncMedia': False})
            assert outcome.get('required') not in ('FULL_SYNC', 'FULL_UPLOAD', 'FULL_DOWNLOAD'), outcome
        assert a.call('SearchService.SearchCards', {'search': '"Only group A"'})['ids']
        assert not b.call('SearchService.SearchCards', {'search': '"Only group A"'}).get('ids', [])
        assert b.call('SearchService.SearchCards', {'search': ''})['ids'] == before_b
        print('PASS: concurrent proxy downloads and independent manual/automatic server mutations')
    finally:
        for engine in clients:
            engine.close()
        for child in reversed(processes):
            child.terminate()
        for child in reversed(processes):
            try: child.wait(timeout=5)
            except subprocess.TimeoutExpired: child.kill(); child.wait()
        for stream in streams: stream.close()

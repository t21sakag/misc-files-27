"""Authenticate and exchange real collections/media between two clients via Anki's own server."""
from engine_smoke import Engine, lib, unpack
import ctypes
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request


def wait_media(engine):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        status = engine.call('SyncService.MediaSyncStatus')
        if not status.get('active'):
            return
        time.sleep(.1)
    raise AssertionError('Media sync did not complete')


def sync(engine, auth, upload=None):
    result = engine.call('SyncService.SyncCollection', {'auth': auth, 'syncMedia': True})
    if result.get('required') in ('FULL_SYNC', 'FULL_UPLOAD', 'FULL_DOWNLOAD'):
        assert upload is not None, result
        engine.call('SyncService.FullUploadOrDownload', {
            'auth': auth, 'upload': upload, 'serverUsn': result.get('serverMediaUsn', 0)})
    wait_media(engine)


with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = os.environ | {'SYNC_USER1': 'fixture:fixture-password', 'SYNC_HOST': '127.0.0.1',
                        'SYNC_PORT': str(port), 'SYNC_BASE': str(root / 'server')}
    with (root / 'server.log').open('w') as log:
        server = subprocess.Popen([str(Path(sys.argv[2]).resolve())], env=env, stdout=log, stderr=log)
        try:
            endpoint = f'http://127.0.0.1:{port}/'
            deadline = time.monotonic() + 30
            while True:
                try:
                    urllib.request.urlopen(endpoint + 'health', timeout=1).close()
                    break
                except OSError:
                    assert server.poll() is None, (root / 'server.log').read_text()
                    assert time.monotonic() < deadline
                    time.sleep(.1)
            a = Engine(root / 'client-a')
            bad = unpack(lib.ap_call(a.handle, b'SyncService.SyncLogin', json.dumps({
                'username': 'fixture', 'password': 'wrong-password', 'endpoint': endpoint}).encode()))
            assert 'error' in bad
            assert bad.get('errorKind') == 7, bad
            auth = a.call('SyncService.SyncLogin', {
                'username': 'fixture', 'password': 'fixture-password', 'endpoint': endpoint})
            assert auth['hkey'] and auth['endpoint'] == endpoint
            note = a.call('NotesService.NewNote', {'ntid': a.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']})
            note['fields'] = ['同期テスト', '最初の答え <img src="sync.svg">']
            nid = a.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
            (a.root / 'collection.media' / 'sync.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>')
            sync(a, auth, upload=True)
            b = Engine(root / 'client-b')
            sync(b, auth, upload=False)
            downloaded = b.call('NotesService.GetNote', {'nid': nid})
            assert downloaded['fields'][0] == '同期テスト'
            assert (b.root / 'collection.media' / 'sync.svg').read_bytes() == (a.root / 'collection.media' / 'sync.svg').read_bytes()
            downloaded['fields'][1] = 'iPad側で編集した答え'
            b.call('NotesService.UpdateNotes', {'notes': [downloaded]})
            sync(b, auth)
            sync(a, auth)
            assert a.call('NotesService.GetNote', {'nid': nid})['fields'][1] == 'iPad側で編集した答え'
            a.close()
            b.close()
            print('PASS: login + rejected password + full upload/download + media + bidirectional incremental sync')
        finally:
            server.terminate()
            server.wait(timeout=10)

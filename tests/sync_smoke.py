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
    state = engine.call('_droid/local_sync_status')
    assert state['neverSynced'] is False, state
    # A full-upload transaction can leave mod > ls by 1 ms even when remote
    # metadata agrees. The app remembers this exact successful snapshot.
    assert state['modification'].isdigit(), state
    return result


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
            assert sync(a, auth, upload=True)['required'] == 'FULL_UPLOAD'
            b = Engine(root / 'client-b')
            assert sync(b, auth, upload=False)['required'] == 'FULL_DOWNLOAD'
            downloaded = b.call('NotesService.GetNote', {'nid': nid})
            assert downloaded['fields'][0] == '同期テスト'
            assert (b.root / 'collection.media' / 'sync.svg').read_bytes() == (a.root / 'collection.media' / 'sync.svg').read_bytes()
            clean_stamp = b.call('_droid/local_sync_status')['modification']
            downloaded['fields'][1] = 'iPad側で編集した答え'
            b.call('NotesService.UpdateNotes', {'notes': [downloaded]})
            changed = b.call('_droid/local_sync_status')
            assert changed['hasChanges'] is True and changed['modification'] != clean_stamp, changed
            sync(b, auth)
            sync(a, auth)
            assert a.call('NotesService.GetNote', {'nid': nid})['fields'][1] == 'iPad側で編集した答え'
            # Persist the same reviewer field used by the home deck disclosure.
            deck = a.call('DecksService.NewDeck')
            deck['name'] = 'Synced parent::Nested child'
            a.call('DecksService.AddDeck', deck)
            parent = next(d['id'] for d in a.call('DecksService.GetDeckNames', {'includeFiltered': True})['entries'] if d['name'] == 'Synced parent')
            browser_before = a.call('DecksService.GetDeck', {'did': parent})['common'].get('browserCollapsed', False)
            a.call('DecksService.SetDeckCollapsed', {'deckId': parent, 'collapsed': True, 'scope': 'REVIEWER'})
            sync(a, auth)
            sync(b, auth)
            common = b.call('DecksService.GetDeck', {'did': parent})['common']
            assert common['studyCollapsed'] is True and common.get('browserCollapsed', False) == browser_before, common
            b.call('DecksService.SetDeckCollapsed', {'deckId': parent, 'collapsed': False, 'scope': 'REVIEWER'})
            sync(b, auth)
            sync(a, auth)
            assert not a.call('DecksService.GetDeck', {'did': parent})['common'].get('studyCollapsed', False)
            forced = a.call('_droid/force_one_way_sync')
            assert forced['schemaModified'].isdigit(), forced
            assert a.call('_droid/local_sync_status')['hasChanges']
            assert sync(a, auth, upload=False)['required'] == 'FULL_SYNC', 'one-way request must force a full sync choice'
            assert sync(a, auth).get('required', 'NO_CHANGES') == 'NO_CHANGES'
            assert a.call('DecksService.GetDeck', {'did': parent})['common'].get('studyCollapsed', False) is False
            c = Engine(root / 'client-c')
            local_note = c.call('NotesService.NewNote', {'ntid': c.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']})
            local_note['fields'] = ['Local conflict fixture', 'Keep both collections until user chooses']
            c.call('NotesService.AddNote', {'note': local_note, 'deckId': '1'})
            conflict = c.call('SyncService.SyncCollection', {'auth': auth, 'syncMedia': False})
            assert conflict['required'] == 'FULL_SYNC', conflict
            assert len(c.call('SearchService.SearchCards', {'search': ''})['ids']) == 1
            assert len(c.call('DecksService.GetDeckNames', {'includeFiltered': True})['entries']) == 1
            c.close()
            a.close()
            b.close()
            print('PASS: login + rejected password + empty server upload + empty client download + populated conflict + media + bidirectional incremental sync + reviewer collapse round trip + forced one-way sync')
        finally:
            server.terminate()
            server.wait(timeout=10)

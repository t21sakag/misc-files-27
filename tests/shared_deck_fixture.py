"""Serve only a newly generated public test deck, never workspace/user files."""
from engine_smoke import Engine
from pathlib import Path
import http.server
import json
import sys
import tempfile
import subprocess
from urllib.parse import urlsplit, parse_qs

output = Path(sys.argv[2]).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'collection')
    deck = engine.call('DecksService.NewDeck')
    deck['name'] = 'Shared fixture'
    did = engine.call('DecksService.AddDeck', deck)['id']
    ntid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note = engine.call('NotesService.NewNote', {'ntid': ntid})
    note['fields'] = ['Shared deck fixture', 'Downloaded by WebKit']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': did})
    engine.call('ImportExportService.ExportAnkiPackage', {'outPath': str(output), 'options': {'withMedia': True}, 'limit': {'wholeCollection': {}}})
    engine.close()
package = output.read_bytes()
photo = output.with_name('shared-photo.png')
subprocess.run([sys.executable, str(Path(__file__).with_name('make_occlusion_image.py')), str(photo)], check=True)
photo_bytes = photo.read_bytes()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/share-photo':
            body = b'<!doctype html><html><head><title>Picture share fixture</title><meta name="viewport" content="width=device-width"></head><body><img alt="Shared picture fixture" src="/share-photo.png" width="512" height="384"></body></html>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
        elif self.path == '/share-photo.png':
            body = photo_bytes
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
        elif self.path == '/share-note':
            body = b'<!doctype html><html><head><title>Share route fixture</title><meta name="viewport" content="width=device-width"></head><body><h1>Share route fixture</h1><p>Public synthetic text for the OS share service.</p></body></html>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
        elif self.path in ('/shared', '/details'):
            details = '<h1>Shared deck fixture</h1><a href="/svc/shared/download-deck/1?t=fixture-key">Download fixture deck</a>'
            listing = '<h1>Shared deck search</h1><a href="/details" onclick="showDeck();return false;">View fixture deck</a>'
            script = '<script>function showDeck(){history.pushState({},"","/details");document.body.innerHTML=' + json.dumps(details) + ';}window.onpopstate=()=>location.reload();</script>'
            body = ('<!doctype html><meta name="viewport" content="width=device-width"><body>' + (listing if self.path == '/shared' else details) + '</body>' + script).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Set-Cookie', 'shared_fixture=1; HttpOnly; SameSite=Lax; Path=/')
        elif urlsplit(self.path).path == '/svc/shared/download-deck/1':
            # Match the live portal: extensionless keyed endpoint, WebKit
            # cookies, then a redirect to the attachment response.
            if parse_qs(urlsplit(self.path).query).get('t') != ['fixture-key'] or 'shared_fixture=1' not in self.headers.get('Cookie', ''):
                self.send_error(403)
                return
            self.send_response(302)
            self.send_header('Location', '/package/fixture')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        elif self.path == '/package/fixture':
            if 'shared_fixture=1' not in self.headers.get('Cookie', ''):
                self.send_error(403)
                return
            body = package
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="shared-fixture.apkg"')
        else:
            self.send_error(404)
            return
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
http.server.ThreadingHTTPServer(('127.0.0.1', 18892), Handler).serve_forever()

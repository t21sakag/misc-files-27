"""Serve only a newly generated public test deck, never workspace/user files."""
from engine_smoke import Engine
from pathlib import Path
import http.server
import json
import sys
import tempfile

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
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/shared', '/details'):
            details = '<h1>Shared deck fixture</h1><a href="/fixture.apkg">Download fixture deck</a>'
            listing = '<h1>Shared deck search</h1><a href="/details" onclick="showDeck();return false;">View fixture deck</a>'
            script = '<script>function showDeck(){history.pushState({},"","/details");document.body.innerHTML=' + json.dumps(details) + ';}window.onpopstate=()=>location.reload();</script>'
            body = ('<!doctype html><meta name="viewport" content="width=device-width"><body>' + (listing if self.path == '/shared' else details) + '</body>' + script).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
        elif self.path == '/fixture.apkg':
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

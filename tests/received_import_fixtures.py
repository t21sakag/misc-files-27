"""Generate synthetic receive packages and verify them through the real engine."""
from engine_smoke import Engine
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile

out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
svg = b'<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="green"/></svg>'
def open_again(engine):
    engine.call('CollectionService.OpenCollection', {
        'collectionPath': str(engine.root/'collection.anki2'),
        'mediaFolderPath': str(engine.root/'collection.media'),
        'mediaDbPath': str(engine.root/'collection.media.db2')})
def make_note(engine, text):
    ntid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note = engine.call('NotesService.NewNote', {'ntid': ntid})
    note['fields'] = [text + '<img src="received-fixture.svg">', 'Received fixture answer']
    engine.call('MediaService.AddMediaFile', {'desiredName': 'received-fixture.svg', 'data': base64.b64encode(svg).decode()})
    return engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    source = Engine(root/'package-source')
    make_note(source, 'Received APKG question')
    package = out/'received.apkg'
    source.call('ImportExportService.ExportAnkiPackage', {'outPath': str(package),
        'options': {'withMedia': True, 'withScheduling': True}, 'limit': {'wholeCollection': {}}})
    source.close()
    imported = Engine(root/'package-destination')
    options = imported.call('ImportExportService.GetImportAnkiPackagePresets')
    imported.call('ImportExportService.ImportAnkiPackage', {'packagePath': str(package), 'options': options})
    assert len(imported.call('SearchService.SearchCards', {'search': '"Received APKG question"'})['ids']) == 1
    assert (imported.root/'collection.media/received-fixture.svg').read_bytes() == svg
    imported.close()
    source = Engine(root/'collection-source')
    make_note(source, 'Received COLPKG question')
    collection = out/'received.colpkg'
    source.call('ImportExportService.ExportCollectionPackage', {'outPath': str(collection), 'includeMedia': True})
    open_again(source)
    source.close()
    imported = Engine(root/'collection-destination')
    make_note(imported, 'Replaced synthetic question')
    imported.call('CollectionService.CloseCollection')
    imported.call('ImportExportService.ImportCollectionPackage', {
        'colPath': str(imported.root/'collection.anki2'), 'backupPath': str(collection),
        'mediaFolder': str(imported.root/'collection.media'), 'mediaDb': str(imported.root/'collection.media.db2')})
    open_again(imported)
    assert len(imported.call('SearchService.SearchCards', {'search': '"Received COLPKG question"'})['ids']) == 1
    assert not imported.call('SearchService.SearchCards', {'search': '"Replaced synthetic question"'}).get('ids', [])
    assert (imported.root/'collection.media/received-fixture.svg').read_bytes() == svg
    imported.close()
    text = root/'received.tsv'
    text.write_text('#separator:Tab\n#html:false\nReceived TSV question\tReceived TSV answer\n')
    imported = Engine(root/'text-destination')
    ntid = imported.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    metadata = imported.call('ImportExportService.GetCsvMetadata', {'path': str(text), 'notetypeId': ntid, 'deckId': '1'})
    imported.call('ImportExportService.ImportCsv', {'path': str(text), 'metadata': metadata})
    assert imported.call('SearchService.SearchCards', {'search': '"Received TSV question"'}).get('ids')
    imported.close()
manifest = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [package, collection]}
(out/'manifest.json').write_text(json.dumps(manifest, sort_keys=True)+'\n')
print('PASS: synthetic APKG import/media and COLPKG replacement/media and TSV syntax verified through the real engine')

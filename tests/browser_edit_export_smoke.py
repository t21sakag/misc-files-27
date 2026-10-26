from engine_smoke import Engine
from pathlib import Path
import tempfile
import zipfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    engine = Engine(root / 'source')
    tid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    notes = []
    for text in ['Hello Apple', 'hello apple', 'Unselected Apple']:
        note = engine.call('NotesService.NewNote', {'ntid': tid})
        note['fields'] = [text, 'Apple in answer']
        notes.append(engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId'])
    engine.call('SearchService.FindAndReplace', {'nids': notes[:2], 'search': 'Apple', 'replacement': 'Pear', 'matchCase': True})
    assert engine.call('NotesService.GetNote', {'nid': notes[0]})['fields'] == ['Hello Pear', 'Pear in answer']
    assert engine.call('NotesService.GetNote', {'nid': notes[1]})['fields'][0] == 'hello apple'
    assert engine.call('NotesService.GetNote', {'nid': notes[2]})['fields'][0] == 'Unselected Apple'
    field = engine.call('NotetypesService.GetNotetype', {'ntid': tid})['fields'][0]['name']
    engine.call('SearchService.FindAndReplace', {'nids': notes[:2], 'search': '(hello)', 'replacement': '${1}!', 'regex': True, 'matchCase': False, 'fieldName': field})
    assert engine.call('NotesService.GetNote', {'nid': notes[0]})['fields'][0] == 'Hello! Pear'
    card = engine.call('NotesService.CardsOfNote', {'nid': notes[0]})['cids'][0]
    limit = {'cardIds': {'cids': [card]}}
    package = root / 'selected.apkg'
    engine.call('ImportExportService.ExportAnkiPackage', {'outPath': str(package), 'options': {'withMedia': True}, 'limit': limit})
    assert zipfile.is_zipfile(package)
    target = Engine(root / 'target')
    options = target.call('ImportExportService.GetImportAnkiPackagePresets')
    target.call('ImportExportService.ImportAnkiPackage', {'packagePath': str(package), 'options': options})
    imported = target.call('SearchService.SearchCards', {'search': ''})['ids']
    assert len(imported) == 1
    for method in ['ExportCardCsv', 'ExportNoteCsv']:
        path = root / (method + '.txt')
        engine.call('ImportExportService.' + method, {'outPath': str(path), 'withHtml': True, 'limit': limit})
        contents = path.read_text()
        assert 'Hello! Pear' in contents and 'Unselected Apple' not in contents, contents
    target.close(); engine.close()
print('PASS: selected find/replace + case/regex/field semantics + selected APKG round trip + card/note text export')

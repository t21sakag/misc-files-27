"""Real multi-template notes: representative order, scoped results, no scheduling writes."""
from engine_smoke import Engine
from pathlib import Path
import copy
import json
import sys
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory)/'preview')
    basic = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': basic})
    schema['id'] = '0'; schema['name'] = 'Preview two-template fixture'
    second = copy.deepcopy(schema['templates'][0])
    second.pop('ord', None); second['name'] = 'Second preview card'
    second['config']['qFormat'] = 'Second card: ' + second['config']['qFormat']
    schema['templates'].append(second)
    tid = engine.call('NotetypesService.AddNotetype', schema)['id']
    for index in range(3):
        note = engine.call('NotesService.NewNote', {'ntid': tid})
        note['fields'] = [f'PreviewScope {index}', 'Preview answer']
        engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
    # Query using the production browser's note sort configuration.
    engine.call('ConfigService.SetConfigBool', {'key': 'BROWSER_TABLE_SHOW_NOTES_MODE', 'value': True})
    rows = engine.call('SearchService.SearchNotes', {'search': 'PreviewScope', 'order': {'builtin': {'column': 'noteFld', 'reverse': False}}})['ids']
    cards = {nid: engine.call('NotesService.CardsOfNote', {'nid': nid})['cids'] for nid in rows}
    assert len(rows) == 3 and all(len(ids) == 2 for ids in cards.values())
    before = {cid: engine.call('CardsService.GetCard', {'cid': cid}) for ids in cards.values() for cid in ids}
    notes_before = {nid: engine.call('NotesService.GetNote', {'nid': nid}) for nid in rows}
    for nid, ids in cards.items():
        ordinals = [before[cid].get('templateIdx', 0) for cid in ids]
        assert ordinals == [0, 1], ordinals
        for cid in ids:
            rendered = engine.call('CardRenderingService.RenderExistingCard', {'cardId': cid, 'partialRender': True})
            assert any('PreviewScope' in node.get('text', '') for node in rendered['questionNodes'])
            assert before[cid]['noteId'] == nid
            html = ''.join(node.get('text', '') for node in rendered['questionNodes'])
            expected = notes_before[nid]['fields'][0]
            if before[cid].get('templateIdx', 0) == 1: expected = 'Second card: ' + expected
            assert engine.call('CardRenderingService.HtmlToTextLine', {'text': html, 'preserveMediaFilenames': True})['val'] == expected
    # A filtered browser result must not accidentally expand back to all notes.
    scoped = engine.call('SearchService.SearchNotes', {'search': '"PreviewScope 1"'})['ids']
    assert len(scoped) == 1 and scoped[0] in rows
    assert before == {cid: engine.call('CardsService.GetCard', {'cid': cid}) for ids in cards.values() for cid in ids}
    assert notes_before == {nid: engine.call('NotesService.GetNote', {'nid': nid}) for nid in rows}
    if len(sys.argv) > 2:
        Path(sys.argv[2]).write_text(json.dumps({'rows': rows, 'cards': cards})+'\n')
    if len(sys.argv) > 3:
        package = Path(sys.argv[3]).resolve()
        package.parent.mkdir(parents=True, exist_ok=True)
        engine.call('ImportExportService.ExportAnkiPackage', {
            'outPath': str(package), 'options': {'withMedia': False, 'withScheduling': False},
            'limit': {'wholeCollection': {}}})
        destination = Engine(Path(directory)/'imported-preview')
        presets = destination.call('ImportExportService.GetImportAnkiPackagePresets')
        destination.call('ImportExportService.ImportAnkiPackage', {'packagePath': str(package), 'options': presets})
        imported = destination.call('SearchService.SearchNotes', {'search': 'PreviewScope'})['ids']
        assert len(imported) == 3
        imported_cards = [destination.call('NotesService.CardsOfNote', {'nid': nid})['cids'] for nid in imported]
        assert all(len(ids) == 2 for ids in imported_cards)
        assert len(destination.call('SearchService.SearchCards', {'search': 'PreviewScope'})['ids']) == 6
        destination.close()
        print('PASS: small synthetic preview APKG reimports as three notes and six real cards')
    engine.close()
print('PASS: real two-template note/card ordering, filtered row scope and rendered content; card/note scheduling unchanged')

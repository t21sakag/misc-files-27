from engine_smoke import Engine, lib, unpack
from pathlib import Path
import base64
import json
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'browser')
    type_id = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note_ids = []
    for index in range(150):
        note = engine.call('NotesService.NewNote', {'ntid': type_id})
        note['fields'] = [f'Browser {index:03}', f'Answer {index:03}']
        note_ids.append(engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId'])
    columns = engine.call('SearchService.AllBrowserColumns')['columns']
    assert any(c['key'] == 'cardDue' and c['cardsModeLabel'] for c in columns)
    ids = engine.call('SearchService.SearchCards', {'search': '', 'order': {'builtin': {'column': 'noteFld'}}})['ids']
    assert len(ids) == 150
    engine.call('SearchService.SetActiveBrowserColumns', {'vals': ['noteFld', 'template', 'cardDue', 'deck']})
    row = engine.call('SearchService.BrowserRowForId', {'val': ids[0]})
    assert len(row['cells']) == 4 and row['cells'][0]['text'] == 'Browser 000', row
    # Resolve all selected cards, including the 50 not loaded in the first UI page.
    resolved = engine.call('SearchService.SearchNotes', {'search': 'cid:' + ','.join(ids)})['ids']
    assert set(resolved) == set(note_ids)
    saved = {'Recent': 'added:7', 'Tagged': 'tag:example'}
    engine.call('ConfigService.SetConfigJson', {'key': 'savedFilters', 'valueJson': base64.b64encode(json.dumps(saved).encode()).decode()})
    value = engine.call('ConfigService.GetConfigJson', {'val': 'savedFilters'})['json']
    assert json.loads(base64.b64decode(value)) == saved
    engine.call('ConfigService.SetConfigBool', {'key': 'BROWSER_TABLE_SHOW_NOTES_MODE', 'value': True})
    engine.call('SearchService.SetActiveBrowserColumns', {'vals': ['noteFld', 'note', 'template', 'noteTags']})
    notes = engine.call('SearchService.SearchNotes', {'search': '"Browser 000"'})['ids']
    row = engine.call('SearchService.BrowserRowForId', {'val': notes[0]})
    assert row['cells'][0]['text'] == 'Browser 000'
    engine.call('ConfigService.SetConfigBool', {'key': 'BROWSER_TABLE_SHOW_NOTES_MODE', 'value': False})
    engine.call('SchedulerService.SortCards', {'cardIds': ids[:3], 'startingFrom': 5, 'stepSize': 3, 'shiftExisting': False})
    assert [engine.call('CardsService.GetCard', {'cid': card})['due'] for card in ids[:3]] == [5, 8, 11]
    for card in ids[:3]:
        engine.call('CardRenderingService.RenderExistingCard', {'cardId': card})
        assert engine.call('CardsService.GetCard', {'cid': card}).get('reps', 0) == 0
    other = engine.call('DecksService.NewDeck')
    other['name'] = 'Other scope'
    other_id = engine.call('DecksService.AddDeck', other)['id']
    outside = engine.call('NotesService.NewNote', {'ntid': type_id})
    outside['fields'] = ['Outside scope', 'Must not appear in selected-deck search']
    engine.call('NotesService.AddNote', {'note': outside, 'deckId': other_id})
    selected_name = engine.call('DecksService.GetDeck', {'did': '1'})['name']
    grouped = engine.call('SearchService.BuildSearchString', {'group': {'joiner': 'AND', 'nodes': [{'deck': selected_name}, {'parsableText': '"Browser 000" or "Outside scope"'}]}})['val']
    scoped = engine.call('SearchService.SearchCards', {'search': grouped})['ids']
    assert scoped == [ids[0]], (grouped, scoped)
    engine.close()
print('PASS: browser columns + sorting + notes/cards modes + saved searches + all-page selection + reposition + read-only preview')

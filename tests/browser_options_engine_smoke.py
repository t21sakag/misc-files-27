"""Real backend search/preferences contracts; UI draft save/cancel is separate."""
from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory) / 'browser-options'
    engine = Engine(root)
    tid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note = engine.call('NotesService.NewNote', {'ntid': tid})
    note['fields'] = ['café', 'Accent search fixture']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
    for value, expected in [(False, 0), (True, 1)]:
        engine.call('ConfigService.SetConfigBool', {'key': 'IGNORE_ACCENTS_IN_SEARCH', 'value': value})
        assert len(engine.call('SearchService.SearchCards', {'search': 'cafe'}).get('ids', [])) == expected
    engine.call('ConfigService.SetConfigBool', {'key': 'BROWSER_TABLE_SHOW_NOTES_MODE', 'value': True})
    engine.call('ConfigService.SetConfigString', {'key': 'DEFAULT_SEARCH_TEXT', 'value': 'cafe'})
    engine.close()
    engine = Engine(root)
    assert engine.call('ConfigService.GetConfigBool', {'key': 'IGNORE_ACCENTS_IN_SEARCH'})['val']
    assert engine.call('ConfigService.GetConfigBool', {'key': 'BROWSER_TABLE_SHOW_NOTES_MODE'})['val']
    assert engine.call('ConfigService.GetConfigString', {'key': 'DEFAULT_SEARCH_TEXT'})['val'] == 'cafe'
    assert len(engine.call('SearchService.SearchNotes', {'search': 'cafe'})['ids']) == 1
    engine.close()
print('PASS: real accent-sensitive search and notes/default-search preferences survive collection reopen')

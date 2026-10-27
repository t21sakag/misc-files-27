"""Read real offline sync state; no network access or user data."""
from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'collection')
    state = engine.call('_droid/local_sync_status')
    assert state == {'neverSynced': True, 'hasChanges': False}, state
    note = engine.call('NotesService.NewNote', {'ntid': engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']})
    note['fields'] = ['Unsynced note', 'Offline sync indicator']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
    state = engine.call('_droid/local_sync_status')
    assert state == {'neverSynced': True, 'hasChanges': True}, state
    engine.close()
    engine = Engine(Path(directory) / 'collection')
    assert engine.call('_droid/local_sync_status') == state
    engine.close()
    print('PASS: empty first-sync state, unsynced card and offline state after reopen')

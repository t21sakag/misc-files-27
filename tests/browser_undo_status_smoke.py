"""Production Swift availability adapter against real session-only Undo/Redo."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from engine_smoke import Engine

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    engine = Engine(root/'collection')
    child = subprocess.Popen([sys.argv[2]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def status(collection, fail=False):
        child.stdin.write('read\n')
        child.stdin.flush()
        request = json.loads(child.stdout.readline())
        assert request == {'method': 'CollectionService.GetUndoStatus'}, request
        response = {'error': True} if fail else {'ok': collection.call(request['method'])}
        child.stdin.write(json.dumps(response)+'\n')
        child.stdin.flush()
        return json.loads(child.stdout.readline())

    try:
        assert status(engine) == {'undo': '', 'redo': ''}
        tid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
        note = engine.call('NotesService.NewNote', {'ntid': tid})
        note['fields'] = ['Undo menu fixture', 'Answer']
        engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
        added = status(engine)
        assert added['undo'] and not added['redo'], added
        engine.call('SearchService.SearchCards', {'search': ''})
        assert status(engine) == added, 'Reading browser results must preserve the action'
        engine.call('CollectionService.Undo')
        undone = status(engine)
        assert not undone['undo'] and undone['redo'] == added['undo'], undone
        assert not engine.call('SearchService.SearchCards', {'search': ''}).get('ids')
        engine.call('CollectionService.Redo')
        assert status(engine) == added
        assert len(engine.call('SearchService.SearchCards', {'search': ''})['ids']) == 1
        assert status(engine, fail=True) == {'error': True}, 'Read errors must propagate'
        engine.close()
        engine = Engine(root/'collection')
        assert status(engine) == {'undo': '', 'redo': ''}, 'Reopen must not restore cached Undo'
        other = Engine(root/'other-profile')
        try:
            assert status(other) == {'undo': '', 'redo': ''}, 'Profiles must not share availability'
        finally:
            other.close()
        child.stdin.close()
        assert child.wait(timeout=10) == 0
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        engine.close()

print('PASS: production Swift/CABI Undo/Redo names, availability, search preservation, errors, reopen and profile isolation')

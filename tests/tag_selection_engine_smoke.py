"""Production Swift tag-selection adapter -> actual native C ABI: tri-state load, partial preservation, atomic Undo, and pre-write validation."""
from engine_smoke import Engine, lib, unpack
from pathlib import Path
import json, subprocess, sys, tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'collection')
    child = subprocess.Popen([sys.argv[2]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def operate(payload):
        child.stdin.write(json.dumps(payload) + '\n')
        child.stdin.flush()
        calls = []
        while True:
            line = child.stdout.readline()
            assert line, 'Swift tag adapter exited'
            value = json.loads(line)
            if 'done' in value:
                return value, calls
            method = value['method']
            calls.append(method)
            result = unpack(lib.ap_call(engine.handle, method.encode(), json.dumps(value['args']).encode()))
            reply = {'ok': result['ok']} if 'ok' in result else {'error': result['error'], 'kind': result.get('errorKind')}
            child.stdin.write(json.dumps(reply) + '\n')
            child.stdin.flush()

    def add_note(front, back, tags):
        ntid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
        note = engine.call('NotesService.NewNote', {'ntid': ntid})
        note['fields'] = [front, back]
        note['tags'] = tags
        return engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']

    def note_tags(nid):
        return engine.call('NotesService.GetNote', {'nid': nid})['tags']

    try:
        n1 = add_note('Q1', 'A1', ['common', 'science::physics'])
        n2 = add_note('Q2', 'A2', ['common', 'history'])

        loaded, calls = operate({'op': 'load', 'noteIDs': [n1, n2]})
        assert loaded['done'], loaded
        assert loaded['checkedTags'] == ['common'], loaded
        assert set(loaded['partiallySelectedTags']) == {'science::physics', 'history'}, loaded
        # Display ancestor 'science' is in indeterminateTags but NOT in partiallySelectedTags
        assert 'science' in loaded['indeterminateTags'], loaded
        assert 'science' not in loaded['partiallySelectedTags'], loaded

        # Apply batch edit: keep 'science::physics' and 'history' partial, add 'reviewed' to all
        applied, calls = operate({
            'op': 'apply',
            'noteIDs': [n1, n2],
            'checkedTags': ['common', 'reviewed'],
            'partiallySelectedTags': loaded['partiallySelectedTags']
        })
        assert applied['done'], applied
        assert calls.count('NotesService.UpdateNotes') == 1, calls
        assert set(note_tags(n1)) == {'common', 'science::physics', 'reviewed'}
        assert set(note_tags(n2)) == {'common', 'history', 'reviewed'}

        # Single Undo restores both notes atomically to their exact prior per-note tags
        engine.call('CollectionService.Undo')
        assert set(note_tags(n1)) == {'common', 'science::physics'}
        assert set(note_tags(n2)) == {'common', 'history'}

        # Invalid/missing/duplicate note IDs fail before any UpdateNotes call
        for bad_ids in [[], [n1, '9223372036854775807'], [n1, n1], ['0']]:
            failed, calls = operate({
                'op': 'apply',
                'noteIDs': bad_ids,
                'checkedTags': ['mutated'],
                'partiallySelectedTags': []
            })
            assert not failed['done'] and 'NotesService.UpdateNotes' not in calls, (bad_ids, failed, calls)
            assert set(note_tags(n1)) == {'common', 'science::physics'}
            assert set(note_tags(n2)) == {'common', 'history'}

        child.stdin.close()
        assert child.wait(timeout=10) == 0
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        engine.close()

print('PASS: production TagSelectionEngine tri-state load, display-ancestor separation, partial preservation, single-call atomic Undo, and pre-write validation')

"""Production saved-search actor methods against actual collection config."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from engine_smoke import Engine


def stored(engine):
    try:
        return engine.call('ConfigService.GetConfigJson', {'val': 'savedFilters'})['json']
    except AssertionError as error:
        if error.args[0][1].get('errorKind') == 11:
            return None
        raise


def put(engine, value):
    data = base64.b64encode(json.dumps(value).encode()).decode()
    engine.call('ConfigService.SetConfigJson', {'key': 'savedFilters', 'valueJson': data})


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    engine = Engine(root/'collection')
    child = subprocess.Popen([sys.argv[2]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def operate(collection, value, fail_read=False, fail_write=False):
        writes = 0
        child.stdin.write(json.dumps(value)+'\n')
        child.stdin.flush()
        while True:
            message = json.loads(child.stdout.readline())
            if message.get('done'):
                return message, writes
            assert message['key'] == 'savedFilters', message
            if message['method'] == 'get':
                raw = stored(collection)
                reply = {'ok': False} if fail_read else (
                    {'ok': True, 'missing': True} if raw is None else
                    {'ok': True, 'json': raw})
            else:
                assert message['method'] == 'set'
                writes += 1
                if fail_write:
                    reply = {'ok': False}
                else:
                    collection.call('ConfigService.SetConfigJson', {'key': 'savedFilters', 'valueJson': message['json']})
                    reply = {'ok': True}
            child.stdin.write(json.dumps(reply)+'\n')
            child.stdin.flush()

    try:
        assert operate(engine, {'operation': 'get'}) == ({'done': True, 'searches': {}}, 0)
        legacy = {'A': ' original query ', 'Quoted "key":': '"nested": "text"'}
        put(engine, legacy)
        saved, writes = operate(engine, {'operation': 'save', 'name': 'a', 'query': '  日本語 * \n'})
        assert writes == 1 and saved['searches'] == dict(legacy, a='日本語 *')
        before = stored(engine)
        duplicate, writes = operate(engine, {'operation': 'save', 'name': 'A', 'query': 'overwrite'})
        assert duplicate['error'] == 'duplicateName' and writes == 0 and stored(engine) == before
        empty, writes = operate(engine, {'operation': 'save', 'name': '', 'query': 'row'})
        assert empty['error'] == 'emptyName' and writes == 0 and stored(engine) == before
        # An addition outside the browser's old snapshot must survive a later save/removal.
        put(engine, dict(saved['searches'], External='retained'))
        saved, writes = operate(engine, {'operation': 'save', 'name': ' literal name ', 'query': ' row '})
        assert saved['searches']['External'] == 'retained' and saved['searches'][' literal name '] == 'row'
        removed, writes = operate(engine, {'operation': 'remove', 'names': ['A', 'missing', 'A']})
        assert writes == 1 and 'A' not in removed['searches'] and removed['searches']['External'] == 'retained'
        assert operate(engine, {'operation': 'remove', 'names': ['missing']})[1] == 0
        before = stored(engine)
        for failure in [{'fail_read': True}, {'fail_write': True}]:
            result, _ = operate(engine, {'operation': 'save', 'name': 'Failed', 'query': 'row'}, **failure)
            assert result['error'] == 'backend' and stored(engine) == before
        result, _ = operate(engine, {'operation': 'remove', 'names': ['a']}, fail_write=True)
        assert result['error'] == 'backend' and stored(engine) == before
        result, writes = operate(engine, {'operation': 'parallel'})
        assert result['successes'] == 1 and writes == 1
        valid = stored(engine)
        for damaged in [None, [], {'Broken': ['invalid']}, {'Nested': {'query': 'invalid'}}, {'Number': 1}, {'café': 1, 'cafe\u0301': 'query'}, {'café': 'query', 'cafe\u0301': []}]:
            put(engine, damaged)
            before = stored(engine)
            result, writes = operate(engine, {'operation': 'save', 'name': 'Avoid overwrite', 'query': 'row'})
            assert result['error'] == 'invalidData' and writes == 0 and stored(engine) == before
        # Java names are literal. Canonically equivalent spellings must remain
        # independently visible, writable and removable throughout a round trip.
        aliases = {'café': ' first query ', 'cafe\u0301': ' second query '}
        put(engine, aliases)
        loaded, writes = operate(engine, {'operation': 'get'})
        assert writes == 0 and loaded['searches'] == aliases
        saved, writes = operate(engine, {'operation': 'save', 'name': 'Independent', 'query': ' row '})
        assert writes == 1 and saved['searches'] == dict(aliases, Independent='row')
        assert json.loads(base64.b64decode(stored(engine))) == saved['searches']
        for name in aliases:
            before = stored(engine)
            duplicate, writes = operate(engine, {'operation': 'save', 'name': name, 'query': 'overwrite'})
            assert duplicate['error'] == 'duplicateName' and writes == 0 and stored(engine) == before
        removed, writes = operate(engine, {'operation': 'remove', 'names': ['café']})
        assert writes == 1 and 'café' not in removed['searches'] and removed['searches']['cafe\u0301'] == aliases['cafe\u0301']
        saved, writes = operate(engine, {'operation': 'save', 'name': 'café', 'query': ' restored '})
        assert writes == 1 and saved['searches']['café'] == 'restored' and saved['searches']['cafe\u0301'] == aliases['cafe\u0301']
        # Also create the second spelling through the normal save entry point.
        put(engine, {'café': 'original'})
        saved, writes = operate(engine, {'operation': 'save', 'name': 'cafe\u0301', 'query': ' new '})
        assert writes == 1 and saved['searches'] == {'café': 'original', 'cafe\u0301': 'new'}
        engine.close()
        engine = Engine(root/'collection')
        assert operate(engine, {'operation': 'get'})[0]['searches'] == saved['searches']
        special = {'back\\slash"': 'quote " and colon :', 'line\nbreak': 'line\nbreak',
                   'nul\x00key': 'retained', '\U0001f642': 'supplementary', '\ue000': 'private use',
                   '가': 'precomposed', '\u1100\u1161': 'decomposed'}
        put(engine, special)
        loaded, writes = operate(engine, {'operation': 'get'})
        assert writes == 0 and loaded['searches'] == special
        # Match JVM String ordering, including a surrogate pair before E000.
        order = list(loaded['searches'])
        assert order.index('\U0001f642') < order.index('\ue000')
        saved, writes = operate(engine, {'operation': 'save', 'name': 'Another', 'query': ' row '})
        assert writes == 1 and saved['searches'] == dict(special, Another='row')
        removed, writes = operate(engine, {'operation': 'remove', 'names': ['nul\x00key', '가']})
        assert writes == 1 and 'nul\x00key' not in removed['searches'] and '가' not in removed['searches']
        assert removed['searches']['\u1100\u1161'] == special['\u1100\u1161']
        put(engine, json.loads(base64.b64decode(valid)))
        engine.close()
        engine = Engine(root/'collection')
        assert stored(engine) == valid
        other = Engine(root/'other-profile')
        try:
            result, _ = operate(other, {'operation': 'save', 'name': 'a', 'query': 'other profile'})
            assert result['searches'] == {'a': 'other profile'} and stored(engine) == valid
        finally:
            other.close()
        child.stdin.close()
        assert child.wait(timeout=10) == 0
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        engine.close()

print('PASS: production Swift/CABI saved searches preserve duplicates, case, literal names, unrelated additions, failed writes, concurrent same-name requests, literal Unicode identities, invalid data and profiles')

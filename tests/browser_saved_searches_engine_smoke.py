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
                    put(collection, message['value'])
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
        for damaged in [None, [], {'Broken': ['invalid']}, {'café': 'first', 'cafe\u0301': 'second'}]:
            put(engine, damaged)
            before = stored(engine)
            result, writes = operate(engine, {'operation': 'save', 'name': 'Avoid overwrite', 'query': 'row'})
            assert result['error'] == 'invalidData' and writes == 0 and stored(engine) == before
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

print('PASS: production Swift/CABI saved searches preserve duplicates, case, literal names, unrelated additions, failed writes, concurrent same-name requests, invalid data and profiles')

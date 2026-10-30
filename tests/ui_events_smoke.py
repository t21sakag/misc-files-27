"""Validate bounded numeric extraction; never unarchive classes or export text."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('events', root/'scripts/summarize-ui-events.py')
events = importlib.util.module_from_spec(spec); spec.loader.exec_module(events)
uid = plistlib.UID
objects = ['$null', {'eventPaths': uid(2)}, {'NS.objects': [uid(3)]},
           {'pointerEvents': uid(4)}, {'NS.objects': [uid(5)]},
           {'eventType': uid(6), 'coordinate.x': uid(7), 'coordinate.y': uid(8), 'offset': uid(9), 'string': uid(10)},
           1, 638.5, 504.5, 0.05, 'NEVER EXPORT typed text']
data = plistlib.dumps({'$top': {'root': uid(1)}, '$objects': objects}, fmt=plistlib.FMT_BINARY)
assert events.decode(data) == [{'eventType': 1, 'coordinate.x': 638.5, 'coordinate.y': 504.5, 'offset': .05}]
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    (base/'event').write_bytes(data)
    manifest = [{'attachments': [{'exportedFileName': 'event', 'suggestedHumanReadableName': 'Synthesized Event example'}]}]
    (base/'manifest.json').write_text(json.dumps(manifest))
    report = events.summarize(base)
    assert len(report['records']) == 1 and not report['errors']
    assert 'NEVER EXPORT' not in json.dumps(report)
    (base/'event').unlink(); (base/'event').symlink_to(base/'manifest.json')
    assert events.summarize(base)['errors']
    (base/'event').unlink(); (base/'event').write_bytes(b'broken')
    assert events.summarize(base)['errors']
    manifest[0]['attachments'][0]['exportedFileName'] = '../outside'
    (base/'manifest.json').write_text(json.dumps(manifest))
    assert events.summarize(base)['errors']
    (base/'manifest.json').write_text(json.dumps([{'attachments': [{'exportedFileName': 'event', 'suggestedHumanReadableName': 'Synthesized Event example'}] * 600}]))
    assert events.summarize(base)['truncated']
print('PASS: numeric events, text excluded, malformed/path/symlink rejection and bounded records')

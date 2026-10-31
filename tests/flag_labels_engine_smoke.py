"""Real collection JSON/profile persistence; names must not mutate cards."""
from engine_smoke import Engine
from pathlib import Path
import base64
import json
import tempfile


def read(engine):
    return json.loads(base64.b64decode(engine.call('ConfigService.GetConfigJson', {'val': 'flagLabels'})['json']))


def write(engine, value):
    engine.call('ConfigService.SetConfigJson', {'key': 'flagLabels', 'valueJson': base64.b64encode(json.dumps(value).encode()).decode()})


with tempfile.TemporaryDirectory() as directory:
    roots = [Path(directory)/'first', Path(directory)/'second']
    engines = [Engine(root) for root in roots]
    first, second = engines
    tid = first.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note = first.call('NotesService.NewNote', {'ntid': tid})
    note['fields'] = ['Flag-name fixture', 'Unchanged content']
    nid = first.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
    cid = first.call('NotesService.CardsOfNote', {'nid': nid})['cids'][0]
    first.call('CardsService.SetFlag', {'cardIds': [cid], 'flag': 4})
    before_card = first.call('CardsService.GetCard', {'cid': cid})
    before_note = first.call('NotesService.GetNote', {'nid': nid})
    original = {'1': 'Important 📌', '2': ' Keep spaces ', 'future': {'preserved': True}}
    write(first, original)
    write(second, {'1': 'Other profile'})
    assert read(first) == original and read(second) == {'1': 'Other profile'}
    assert first.call('CardsService.GetCard', {'cid': cid}) == before_card
    assert first.call('NotesService.GetNote', {'nid': nid}) == before_note
    assert first.call('SearchService.SearchCards', {'search': 'flag:4'})['ids'] == [cid]
    assert not first.call('SearchService.SearchCards', {'search': 'flag:1'}).get('ids')
    for engine in engines: engine.close()
    for root, expected in zip(roots, [original, {'1': 'Other profile'}]):
        reopened = Engine(root)
        assert read(reopened) == expected
        reopened.close()
print('PASS: real flagLabels JSON survives reopening, profiles remain independent, card/note and numeric flag search unchanged')

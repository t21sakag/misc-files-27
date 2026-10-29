"""Verify the link contract's search terms against the real, unmodified engine.

Swift URL parsing has its own Foundation check. This check does not reimplement it.
"""
from engine_smoke import Engine
import json
from pathlib import Path
import tempfile

examples = json.loads(Path(__file__).with_name('browser_links.json').read_text())
with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory)/'collection')
    ntid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note_ids = {}
    for key, front, back, tags in [
        ('route', 'Route needle +', 'Original route back', ['route']),
        ('japanese', '別のノート', 'Context Japanese Save 保存', []),
    ]:
        note = engine.call('NotesService.NewNote', {'ntid': ntid})
        note['fields'] = [front, back]; note['tags'] = tags
        note_ids[key] = engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
    original = {key: engine.call('NotesService.GetNote', {'nid': nid}) for key, nid in note_ids.items()}
    for example in examples:
        if 'matches' not in example: continue
        cards = engine.call('SearchService.SearchCards', {'search': example['search']}).get('ids', [])
        notes = {engine.call('CardsService.GetCard', {'cid': cid})['noteId'] for cid in cards}
        assert notes == {note_ids[key] for key in example['matches']}, example
    for key, nid in note_ids.items():
        assert engine.call('NotesService.GetNote', {'nid': nid}) == original[key]
    engine.close()
print('PASS: browser link contract queries search actual cards; Japanese/plus/tags/empty queries preserve original notes')

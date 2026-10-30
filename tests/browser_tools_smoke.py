"""Real backend contracts used by browser filtered-deck and replacement screens."""
from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'browser-tools')
    tid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    notes = []
    for front in ['Browser Needle', 'Browser Outside']:
        note = engine.call('NotesService.NewNote', {'ntid': tid})
        note['fields'] = [front, 'Literal $1 and Original']
        note['tags'] = ['Original::Child', 'keep']
        notes.append(engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId'])
    decks_before = engine.call('DecksService.GetDeckNames')['entries']
    draft = engine.call('DecksService.GetOrCreateFilteredDeck', {'did': '0'})
    assert engine.call('DecksService.GetDeckNames')['entries'] == decks_before, 'Opening/cancelling must not persist a deck'
    query = '"Browser Needle" -tag:excluded'
    draft['name'] = 'Browser search scope'
    draft['config']['searchTerms'] = [{'search': query, 'limit': 100, 'order': 'OLDEST_REVIEWED_FIRST'}]
    draft['allowEmpty'] = True
    did = engine.call('DecksService.AddOrUpdateFilteredDeck', draft)['id']
    engine.call('SchedulerService.RebuildFilteredDeck', {'did': did})
    selected = engine.call('SearchService.SearchCards', {'search': 'deck:"Browser search scope"'})['ids']
    assert len(selected) == 1
    assert engine.call('CardsService.GetCard', {'cid': selected[0]})['noteId'] == notes[0]
    stored = engine.call('DecksService.GetOrCreateFilteredDeck', {'did': did})
    assert stored['config']['searchTerms'][0]['search'] == query
    # Selected field replacement leaves the unselected note and front untouched.
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': tid})
    back = schema['fields'][1]['name']
    result = engine.call('SearchService.FindAndReplace', {'nids': notes[:1], 'search': 'Original', 'replacement': 'Selected', 'fieldName': back})
    assert result['count'] == 1
    assert engine.call('NotesService.GetNote', {'nid': notes[1]})['fields'][1].endswith('Original')
    # Empty IDs intentionally mean the complete collection, independently of browser query.
    result = engine.call('SearchService.FindAndReplace', {'nids': [], 'search': 'Browser', 'replacement': 'Changed'})
    assert result['count'] == 2
    result = engine.call('TagsService.FindAndReplaceTag', {'noteIds': notes[:1], 'search': 'Original', 'replacement': 'Selected'})
    assert result['count'] == 1
    assert 'Selected::Child' in engine.call('NotesService.GetNote', {'nid': notes[0]})['tags']
    assert 'Original::Child' in engine.call('NotesService.GetNote', {'nid': notes[1]})['tags']
    result = engine.call('TagsService.FindAndReplaceTag', {'noteIds': [], 'search': 'Child', 'replacement': 'Updated'})
    assert result['count'] == 2
    for nid in notes:
        note = engine.call('NotesService.GetNote', {'nid': nid})
        assert any(tag.endswith('::Updated') for tag in note['tags'])
        assert note['fields'][0].startswith('Changed') and note['fields'][1].startswith('Literal $1')
    engine.call('CollectionService.Undo')
    assert all(any(tag.endswith('::Child') for tag in engine.call('NotesService.GetNote', {'nid': nid})['tags']) for nid in notes)
    engine.close()
print('PASS: filtered draft cancellation/exact search/build and selected/all field/tag replacement with undo')

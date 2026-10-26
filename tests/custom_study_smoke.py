from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'study')
    tid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    for index in range(6):
        note = engine.call('NotesService.NewNote', {'ntid': tid})
        note['fields'] = [f'Custom {index}', 'Answer']
        engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
    filtered = engine.call('DecksService.GetOrCreateFilteredDeck', {'did': '0'})
    filtered['name'] = 'Targeted practice'
    filtered['config']['searchTerms'] = [{'search': 'is:new', 'limit': 3, 'order': 'ADDED'}]
    filtered['config']['reschedule'] = False
    filtered['allowEmpty'] = True
    did = engine.call('DecksService.AddOrUpdateFilteredDeck', filtered)['id']
    engine.call('SchedulerService.RebuildFilteredDeck', {'did': did})
    selected = engine.call('SearchService.SearchCards', {'search': 'deck:"Targeted practice"'})['ids']
    assert len(selected) == 3
    assert all(engine.call('CardsService.GetCard', {'cid': cid})['originalDeckId'] == '1' for cid in selected)
    engine.call('SchedulerService.EmptyFilteredDeck', {'did': did})
    assert all(engine.call('CardsService.GetCard', {'cid': cid})['deckId'] == '1' for cid in selected)
    defaults = engine.call('SchedulerService.CustomStudyDefaults', {'deckId': '1'})
    engine.call('SchedulerService.CustomStudy', {'deckId': '1', 'newLimitDelta': 5})
    updated = engine.call('SchedulerService.CustomStudyDefaults', {'deckId': '1'})
    assert updated['extendNew'] == 5
    engine.call('SchedulerService.CustomStudy', {'deckId': '1', 'cram': {'kind': 'CRAM_KIND_ALL', 'cardLimit': 2}})
    all_cards = engine.call('SearchService.SearchCards', {'search': ''})['ids']
    in_filtered = [cid for cid in all_cards if engine.call('CardsService.GetCard', {'cid': cid}).get('originalDeckId', '0') != '0']
    assert len(in_filtered) == 2
    engine.close()
print('PASS: filtered deck build + original deck restoration + custom study limit increase + cram preview')

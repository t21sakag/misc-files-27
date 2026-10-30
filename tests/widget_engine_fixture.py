"""Observe the actual scheduler without fetching cards or changing selection."""
from engine_smoke import Engine
from pathlib import Path
import json
import sys
import tempfile
import time

with tempfile.TemporaryDirectory() as temporary:
    engine = Engine(Path(temporary) / 'widget')
    note_type = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    deck_ids = []
    for name in ['Widget parent::Child', 'Widget other']:
        deck = engine.call('DecksService.NewDeck')
        deck['name'] = name
        did = engine.call('DecksService.AddDeck', deck)['id']
        deck_ids.append(did)
        note = engine.call('NotesService.NewNote', {'ntid': note_type})
        note['fields'] = ['Widget count ' + name, 'Synthetic only']
        engine.call('NotesService.AddNote', {'note': note, 'deckId': did})
    engine.call('DecksService.SetCurrentDeck', {'did': deck_ids[0]})
    selected = engine.call('DecksService.GetCurrentDeck')
    cards = engine.call('SearchService.SearchCards', {'search': ''})['ids']
    before = [engine.call('CardsService.GetCard', {'cid': cid}) for cid in cards]
    now = int(time.time())
    timing = engine.call('SchedulerService.SchedTimingToday')
    tree = engine.call('DecksService.DeckTree', {'now': str(now)})
    args = {'cutoffMillis': (int(timing['nextDayAt']) - 10 * 86400) * 1000,
            'new': tree.get('newCount', 0), 'learning': tree.get('learnCount', 0), 'review': tree.get('reviewCount', 0)}
    eta = engine.call('_droid/eta', args)
    assert sum(args[key] for key in ['new', 'learning', 'review']) == 2, tree
    assert engine.call('DecksService.GetCurrentDeck') == selected
    assert [engine.call('CardsService.GetCard', {'cid': cid}) for cid in cards] == before
    output = {'now': now, 'count': 2, 'selected': deck_ids[0], 'calls': [
        {'method': 'SchedulerService.SchedTimingToday', 'args': {}, 'result': timing},
        {'method': 'DecksService.DeckTree', 'args': {'now': str(now)}, 'result': tree},
        {'method': '_droid/eta', 'args': args, 'result': eta},
        {'method': 'DecksService.GetCurrentDeck', 'args': {}, 'result': selected}]}
    Path(sys.argv[2]).write_text(json.dumps(output) + '\n')
    engine.close()
print('PASS: real widget root counts include siblings once; ETA/day boundary reads preserve selection and all cards')

"""Check actual scheduler counts needed for conditional notification planning.

Only disposable synthetic collections are used. A future DeckTree timestamp is
not permission to move the collection clock or change a card's due date.
"""
from engine_smoke import Engine
from pathlib import Path
import tempfile
import time

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'collection')
    ntid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    parent = engine.call('DecksService.NewDeck')
    parent['name'] = 'Reminder parent'
    parent_id = engine.call('DecksService.AddDeck', parent)['id']
    child = engine.call('DecksService.NewDeck')
    child['name'] = 'Reminder parent::Child'
    child_id = engine.call('DecksService.AddDeck', child)['id']
    note = engine.call('NotesService.NewNote', {'ntid': ntid})
    note['fields'] = ['Future reminder card', 'Synthetic only']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': child_id})
    cid = engine.call('SearchService.SearchCards', {'search': ''})['ids'][0]
    engine.call('SchedulerService.SetDueDate', {'cardIds': [cid], 'days': '2'})
    original = engine.call('CardsService.GetCard', {'cid': cid})
    engine.call('DecksService.SetDeckCollapsed', {'deckId': parent_id, 'collapsed': True, 'scope': 'REVIEWER'})
    now = int(time.time())
    current = engine.call('DecksService.DeckTree', {'now': str(now)})
    future = engine.call('DecksService.DeckTree', {'now': str(now + 3 * 86400)})
    def find(node, did):
        if node.get('deckId') == did:
            return node
        for child in node.get('children', []):
            found = find(child, did)
            if found is not None:
                return found
        return None
    def count(node):
        return sum(node.get(key, 0) for key in ['newCount', 'learnCount', 'reviewCount'])
    assert count(current) == 0, current
    assert count(future) == 1, future
    assert count(find(future, parent_id)) == 1
    assert count(find(future, child_id)) == 1
    assert find(future, parent_id).get('collapsed') is True
    assert find(future, '999999999999999') is None
    assert engine.call('CardsService.GetCard', {'cid': cid}) == original, 'Forecast must not reschedule the real card'
    assert count(engine.call('DecksService.DeckTree', {'now': str(now)})) == 0
    note = engine.call('NotesService.NewNote', {'ntid': ntid})
    note['fields'] = ['Answer before checking reminder', 'Synthetic only']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': child_id})
    engine.call('DecksService.SetCurrentDeck', {'did': child_id})
    assert not engine.call('SearchService.SearchCards', {'search': 'rated:1'}).get('ids')
    queued = engine.call('SchedulerService.GetQueuedCards', {'fetchLimit': 1})['cards'][0]
    states = queued['states']
    engine.call('SchedulerService.AnswerCard', {'cardId': queued['card']['id'], 'currentState': states['current'], 'newState': states['good'], 'rating': 2, 'answeredAtMillis': str(int(time.time() * 1000)), 'millisecondsTaken': 1000})
    search = engine.call('SearchService.BuildSearchString', {'group': {'joiner': 'AND', 'nodes': [{'deck': 'Reminder parent'}, {'parsableText': 'rated:1'}]}})['val']
    assert engine.call('SearchService.SearchCards', {'search': search})['ids'] == [queued['card']['id']]
    timing = engine.call('SchedulerService.SchedTimingToday')
    assert int(timing['nextDayAt']) > int(time.time())
    engine.close()
print('PASS: future due counts, collapsed subtree scope, no double counting, missing deck, unchanged card, scoped review history and scheduler day boundary')

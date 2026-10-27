"""Real reviewer/browser scope persistence and parent scheduling, using disposable data."""
from engine_smoke import Engine
from pathlib import Path
import tempfile
import time


def find_node(engine, name):
    def find(node):
        if node.get('name') == name:
            return node
        for child in node.get('children', []):
            if found := find(child):
                return found
    return find(engine.call('DecksService.DeckTree', {'now': str(int(time.time()))}))


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory) / 'collection'
    engine = Engine(root)
    deck = engine.call('DecksService.NewDeck')
    deck['name'] = 'Parent::Child::Grandchild'
    did = engine.call('DecksService.AddDeck', deck)['id']
    parent = find_node(engine, 'Parent')['deckId']
    before = engine.call('DecksService.GetDeck', {'did': parent})['common']
    ntid = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    note = engine.call('NotesService.NewNote', {'ntid': ntid})
    note['fields'] = ['Nested review question', 'Nested answer']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': did})
    engine.call('DecksService.SetDeckCollapsed', {'deckId': parent, 'collapsed': True, 'scope': 'REVIEWER'})
    node = find_node(engine, 'Parent')
    assert node['collapsed'] and node['newCount'] == 1, node
    assert node['children'], 'Collapsed children remain in the data for pickers/search'
    engine.close()
    engine = Engine(root)
    assert find_node(engine, 'Parent')['collapsed']
    after = engine.call('DecksService.GetDeck', {'did': parent})['common']
    assert after.get('browserCollapsed', False) == before.get('browserCollapsed', False)
    engine.call('DecksService.SetCurrentDeck', {'did': parent})
    card = engine.call('SchedulerService.GetQueuedCards', {'fetchLimit': 1})['cards'][0]['card']
    assert card['deckId'] == did, card
    engine.call('DecksService.SetDeckCollapsed', {'deckId': parent, 'collapsed': False, 'scope': 'REVIEWER'})
    assert not find_node(engine, 'Parent').get('collapsed', False)
    engine.close()
print('PASS: reviewer collapse persists after reopen; browser untouched; parent counts/scheduling include nested cards')

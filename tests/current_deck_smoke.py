"""Read the actual current deck across selection, reopen, deletion and roots."""
from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    a = Engine(root / 'a')
    b = Engine(root / 'b')
    assert a.call('DecksService.GetCurrentDeck')['id'] == '1'
    deck = a.call('DecksService.NewDeck')
    deck['name'] = 'Selection scope'
    did = a.call('DecksService.AddDeck', deck)['id']
    a.call('DecksService.SetCurrentDeck', {'did': did})
    assert a.call('DecksService.GetCurrentDeck')['id'] == did
    assert b.call('DecksService.GetCurrentDeck')['id'] == '1'
    before = a.call('DecksService.DeckTree')
    assert a.call('DecksService.GetCurrentDeck')['id'] == did
    assert a.call('DecksService.DeckTree') == before
    a.close()
    a = Engine(root / 'a')
    assert a.call('DecksService.GetCurrentDeck')['id'] == did
    a.call('DecksService.RemoveDecks', {'dids': [did]})
    assert a.call('DecksService.GetCurrentDeck')['id'] == '1'
    a.close(); b.close()
print('PASS: actual current deck selection, reopen, deletion fallback, read-only tree and independent roots')

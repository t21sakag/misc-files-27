"""Use real per-handle translations and reopen existing data under new locales."""
from engine_smoke import Engine, lib, unpack
import base64
import ctypes
import json
from pathlib import Path
import sqlite3
import tempfile
import time

lib.ap_open_with_languages.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
lib.ap_open_with_languages.restype = ctypes.c_void_p


class LocalizedEngine(Engine):
    def __init__(self, root, languages):
        error = ctypes.c_void_p()
        self.handle = lib.ap_open_with_languages(json.dumps(languages).encode(), ctypes.byref(error))
        assert self.handle, unpack(error.value) if error.value else 'No backend'
        assert not error.value
        self.root = root
        root.mkdir(parents=True, exist_ok=True)
        (root/'collection.media').mkdir(exist_ok=True)
        self.call('CollectionService.OpenCollection', {
            'collectionPath': str(root/'collection.anki2'),
            'mediaFolderPath': str(root/'collection.media'),
            'mediaDbPath': str(root/'collection.media.db2'),
        })


def again(engine):
    data = engine.call('I18nService.I18nResources', {'modules': ['studying']})['json']
    resources = json.loads(base64.b64decode(data))['resources']
    return next(line for line in resources[0].splitlines() if line.startswith('studying-again ='))


def day(engine):
    value = engine.call('I18nService.FormatTimespan', {'seconds': 86400, 'context': 2})['val']
    # Fluent may isolate interpolated numbers for bidirectional text.
    return value.replace('\u2068', '').replace('\u2069', '')


for invalid in [None, b'null', b'{}', b'["ja",7]', b'["ja"] trailing', b'\xff']:
    error = ctypes.c_void_p()
    assert not lib.ap_open_with_languages(invalid, ctypes.byref(error))
    assert error.value and 'error' in unpack(error.value)
assert not lib.ap_open_with_languages(b'not json', None)

with tempfile.TemporaryDirectory() as folder:
    base = Path(folder)
    legacy = Engine(base/'legacy')
    assert again(legacy) == 'studying-again = もう一度'
    for languages, expected, interval in [
        (['en'], 'Again', '1 day'), (['fr'], 'À revoir', '1 jour'),
        (['ja'], 'もう一度', '1 日'), ([], 'Again', '1 day'),
        (['zz-ZZ'], 'Again', '1 day'), (['zz-ZZ', 'fr', 'ja'], 'À revoir', '1 jour'),
        (['en', 'fr'], 'Again', '1 day'), (['ja', 'en'], 'もう一度', '1 日'),
    ]:
        other = LocalizedEngine(base/'other', languages)
        assert again(other) == 'studying-again = '+expected
        assert day(other) == interval
        assert again(legacy) == 'studying-again = もう一度', 'Translations leaked between handles'
        assert day(legacy) == '1 日', 'Formatted translations leaked between handles'
        print(f'{languages!r}: {expected}; {interval}')
        other.close()
    type_id = legacy.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    deck = legacy.call('DecksService.NewDeck'); deck['name'] = 'Save 保存 user deck'
    did = legacy.call('DecksService.AddDeck', deck)['id']
    note = legacy.call('NotesService.NewNote', {'ntid': type_id})
    note['fields'] = ['Save 保存 original <img src="locale.bin">', 'Answer 解答 original']
    nid = legacy.call('NotesService.AddNote', {'note': note, 'deckId': did})['noteId']
    media = legacy.root/'collection.media/locale.bin'; media.write_bytes(b'original media preservation marker')
    legacy.call('DecksService.SetCurrentDeck', {'did': did})
    queued = legacy.call('SchedulerService.GetQueuedCards', {'fetchLimit': 1})['cards'][0]
    legacy.call('SchedulerService.AnswerCard', {
        'cardId': queued['card']['id'], 'currentState': queued['states']['current'], 'newState': queued['states']['good'],
        'rating': 2, 'answeredAtMillis': str(int(time.time()*1000)), 'millisecondsTaken': 2000,
    })
    saved_note = legacy.call('NotesService.GetNote', {'nid': nid})
    saved_deck = legacy.call('DecksService.GetDeck', {'did': did})
    saved_card = legacy.call('CardsService.GetCard', {'cid': queued['card']['id']})
    saved_types = legacy.call('NotetypesService.GetNotetypeNames')
    legacy.close()
    with sqlite3.connect(base/'legacy/collection.anki2') as db:
        history = db.execute('select * from revlog order by id').fetchall()
    assert len(history) == 1
    for languages, expected in [(['en'], 'Again'), (['fr'], 'À revoir'), (['ja'], 'もう一度')]:
        reopened = LocalizedEngine(base/'legacy', languages)
        assert again(reopened) == 'studying-again = '+expected
        assert reopened.call('DecksService.GetDeck', {'did': did}) == saved_deck
        assert reopened.call('NotesService.GetNote', {'nid': nid}) == saved_note
        assert reopened.call('CardsService.GetCard', {'cid': queued['card']['id']}) == saved_card
        assert reopened.call('NotetypesService.GetNotetypeNames') == saved_types
        assert reopened.call('DecksService.GetCurrentDeck')['id'] == did
        assert media.read_bytes() == b'original media preservation marker'
        reopened.close()
        with sqlite3.connect(base/'legacy/collection.anki2') as db:
            assert db.execute('select * from revlog order by id').fetchall() == history
print('PASS: real ja/en/fr translations, English fallback, independent handles, malformed init, existing deck/note/types/card/history/media preservation')

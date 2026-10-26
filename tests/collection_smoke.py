from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'collection')
    deck = engine.call('DecksService.NewDeck')
    deck['name'] = 'iPad作成デッキ'
    did = engine.call('DecksService.AddDeck', deck)['id']
    engine.call('DecksService.RenameDeck', {'deckId': did, 'newName': 'iPad編集デッキ'})
    assert engine.call('DecksService.GetDeck', {'did': did})['name'] == 'iPad編集デッキ'
    type_id = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': type_id})
    assert len(schema['fields']) >= 2
    note = engine.call('NotesService.NewNote', {'ntid': type_id})
    note['fields'] = ['作成した質問', '作成した解答']
    note['tags'] = ['iPad', '編集テスト']
    nid = engine.call('NotesService.AddNote', {'note': note, 'deckId': did})['noteId']
    note = engine.call('NotesService.GetNote', {'nid': nid})
    note['fields'][1] = '<b>編集した解答</b>'
    engine.call('NotesService.UpdateNotes', {'notes': [note]})
    ids = engine.call('SearchService.SearchCards', {'search': 'tag:iPad', 'order': {'builtin': {'column': 'noteFld'}}})['ids']
    assert len(ids) == 1
    assert engine.call('CardRenderingService.StripHtml', {'text': note['fields'][1]})['val'] == '編集した解答'
    engine.call('CardsService.SetFlag', {'cardIds': ids, 'flag': 3})
    assert engine.call('CardsService.GetCard', {'cid': ids[0]})['flags'] & 7 == 3
    engine.call('SchedulerService.BuryOrSuspendCards', {'cardIds': ids, 'mode': 'SUSPEND'})
    assert engine.call('CardsService.GetCard', {'cid': ids[0]})['queue'] == -1
    engine.call('SchedulerService.RestoreBuriedAndSuspendedCards', {'cids': ids})
    assert engine.call('CardsService.GetCard', {'cid': ids[0]}).get('queue', 0) >= 0
    engine.call('CardsService.SetDeck', {'cardIds': ids, 'deckId': '1'})
    assert engine.call('CardsService.GetCard', {'cid': ids[0]})['deckId'] == '1'
    engine.call('TagsService.AddNoteTags', {'noteIds': [nid], 'tags': '追加タグ'})
    assert '追加タグ' in engine.call('NotesService.GetNote', {'nid': nid})['tags']
    engine.call('TagsService.RemoveNoteTags', {'noteIds': [nid], 'tags': '追加タグ'})
    assert '追加タグ' not in engine.call('NotesService.GetNote', {'nid': nid})['tags']
    engine.call('TagsService.AddNoteTags', {'noteIds': [nid], 'tags': '管理::子 管理外'})
    engine.call('TagsService.RenameTags', {'currentPrefix': '管理', 'newPrefix': '変更'})
    renamed_tags = engine.call('NotesService.GetNote', {'nid': nid})['tags']
    assert '変更::子' in renamed_tags and '管理外' in renamed_tags and '管理::子' not in renamed_tags
    engine.call('TagsService.ReparentTags', {'tags': ['変更'], 'newParent': '親'})
    assert '親::変更::子' in engine.call('NotesService.GetNote', {'nid': nid})['tags']
    def tag_node(path):
        node = engine.call('TagsService.TagTree')
        for component in path.split('::'):
            node = next(child for child in node.get('children', []) if child['name'] == component)
        return node
    engine.call('TagsService.SetTagCollapsed', {'name': '親::変更', 'collapsed': False})
    assert not tag_node('親::変更').get('collapsed', False)
    assert tag_node('親::変更::子')['name'] == '子'
    engine.call('TagsService.SetTagCollapsed', {'name': '親::変更', 'collapsed': True})
    assert tag_node('親::変更')['collapsed'] is True
    assert '親::変更::子' in engine.call('NotesService.GetNote', {'nid': nid})['tags']
    engine.call('TagsService.RemoveTags', {'val': '親::変更'})
    removed_tags = engine.call('NotesService.GetNote', {'nid': nid})['tags']
    assert '親::変更::子' not in removed_tags and '管理外' in removed_tags and 'iPad' in removed_tags
    assert engine.call('NotesService.GetNote', {'nid': nid})['fields'][1] == '<b>編集した解答</b>'
    engine.call('CollectionService.Undo')
    assert '親::変更::子' in engine.call('NotesService.GetNote', {'nid': nid})['tags']
    engine.call('TagsService.RemoveTags', {'val': '親::変更 管理外'})
    engine.call('TagsService.ClearUnusedTags')
    registered_tags = engine.call('TagsService.AllTags')['vals']
    assert '追加タグ' not in registered_tags and 'iPad' in registered_tags
    engine.call('SchedulerService.SetDueDate', {'cardIds': ids, 'days': '3'})
    engine.call('SchedulerService.ScheduleCardsAsNew', {'cardIds': ids, 'log': True, 'restorePosition': True})
    engine.call('NotesService.RemoveNotes', {'noteIds': [nid]})
    assert not engine.call('SearchService.SearchCards', {'search': 'tag:iPad'}).get('ids')
    engine.call('CollectionService.Undo')
    assert engine.call('SearchService.SearchCards', {'search': 'tag:iPad'})['ids'] == ids
    engine.call('DecksService.RemoveDecks', {'dids': [did]})
    assert all(d['id'] != did for d in engine.call('DecksService.GetDeckNames')['entries'])
    engine.close()
print('PASS: deck/note CRUD + HTML + search + flags + suspend/restore + move + tags + reschedule + delete/undo')

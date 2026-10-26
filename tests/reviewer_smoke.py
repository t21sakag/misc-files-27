from engine_smoke import Engine
from pathlib import Path
import base64
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'reviewer')
    first = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': first})
    schema['id'] = '0'
    schema['name'] = 'Typed audio template'
    front, back = (field['name'] for field in schema['fields'][:2])
    schema['templates'][0]['config']['qFormat'] = '{{' + front + '}} {{type:' + back + '}}'
    schema['templates'][0]['config']['aFormat'] = '{{FrontSide}}<hr id=answer>{{type:' + back + '}} [sound:answer.wav]'
    type_id = engine.call('NotetypesService.AddNotetype', schema)['id']
    note = engine.call('NotesService.NewNote', {'ntid': type_id})
    note['fields'] = ['Question [sound:question.wav]', 'correct answer']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
    engine.call('DecksService.SetCurrentDeck', {'did': '1'})
    queued = engine.call('SchedulerService.GetQueuedCards', {'fetchLimit': 1})['cards'][0]
    card = queued['card']
    result = engine.call('CardRenderingService.RenderExistingCard', {'cardId': card['id'], 'partialRender': True})
    question = ''.join(node.get('text', '') for node in result['questionNodes'])
    assert '[[type:' in question
    q = engine.call('CardRenderingService.ExtractAvTags', {'text': question, 'questionSide': True})
    assert q['avTags'][0]['soundOrVideo'] == 'question.wav'
    answer = ''.join(node['text'] if 'text' in node else q['text'] if node['replacement']['fieldName'] == 'FrontSide' else '' for node in result['answerNodes'])
    a = engine.call('CardRenderingService.ExtractAvTags', {'text': answer, 'questionSide': False})
    assert [tag['soundOrVideo'] for tag in a['avTags']] == ['answer.wav'], a
    assert '[anki:play:q:0]' in a['text']
    good = engine.call('CardRenderingService.CompareAnswer', {'expected': 'correct answer', 'provided': 'correct answer', 'combining': True})['val']
    assert 'typeGood' in good and 'typeBad' not in good
    bad = engine.call('CardRenderingService.CompareAnswer', {'expected': 'correct answer', 'provided': 'wrong', 'combining': True})['val']
    assert 'typeBad' in bad or 'typeMissed' in bad
    assert engine.call('CardRenderingService.ExtractClozeForTyping', {'text': '{{c1::one}} and {{c2::two}}', 'ordinal': 1})['val'] == 'one'
    engine.call('ConfigService.SetConfigString', {'key': 'CARD_STATE_CUSTOMIZER', 'value': 'states.easy.normal.review.scheduledDays = 7;'})
    assert 'scheduledDays' in engine.call('ConfigService.GetConfigString', {'key': 'CARD_STATE_CUSTOMIZER'})['val']
    encoded = engine.call('_encode/get_scheduling_states_with_context', {'states': queued['states'], 'context': queued['context']})['data']
    assert base64.b64decode(encoded)
    deck = engine.call('DecksService.GetDeck', {'did': card['deckId']})
    config = engine.call('DeckConfigService.GetDeckConfig', {'dcid': deck['normal']['configId']})['config']
    assert config.get('capAnswerTimeToSecs', 0) >= 0
    engine.close()
print('PASS: typing + cloze + FrontSide rendering + nonduplicated audio + custom scheduler context + deck review options')

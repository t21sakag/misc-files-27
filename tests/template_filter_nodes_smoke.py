from engine_smoke import Engine
from pathlib import Path
import json
import sys
import tempfile

cases = []
with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'collection')
    original = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': original})
    front = schema['fields'][0]['name']
    schema['id'] = '0'
    schema['name'] = 'Unknown filter compatibility'
    schema['templates'][0]['config']['qFormat'] = '{{unknown_filter:' + front + '}}'
    schema['templates'][0]['config']['aFormat'] = '{{unknown_filter:FrontSide}}<hr id=answer>Answer'
    type_id = engine.call('NotetypesService.AddNotetype', schema)['id']
    note = engine.call('NotesService.NewNote', {'ntid': type_id})
    note['fields'] = ['Filter content', 'Back']
    engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
    cid = engine.call('SearchService.SearchCards', {'search': ''})['ids'][0]
    rendered = engine.call('CardRenderingService.RenderExistingCard', {'cardId': cid, 'partialRender': True})
    assert rendered['questionNodes'][0]['replacement']['currentText'] == 'Filter content'
    cases.append({'nodes': rendered['questionNodes'], 'expected': 'Filter content'})
    cases.append({'nodes': rendered['answerNodes'], 'front': 'Processed front', 'expected': 'Processed front<hr id=answer>Answer'})
    cases.append({'nodes': rendered['answerNodes'], 'front': '', 'expected': '<hr id=answer>Answer'})
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': type_id})
    note = engine.call('NotesService.GetNote', {'nid': engine.call('SearchService.SearchNotes', {'search': ''})['ids'][0]})
    uncommitted = engine.call('CardRenderingService.RenderUncommittedCard', {'note': note, 'cardOrd': 0, 'template': schema['templates'][0], 'fillEmpty': False})
    cases.append({'nodes': uncommitted['questionNodes'], 'expected': 'Filter content'})
    cases.append({'nodes': uncommitted['answerNodes'], 'front': 'Unsaved front', 'expected': 'Unsaved front<hr id=answer>Answer'})
    engine.close()
Path(sys.argv[2]).write_text(json.dumps(cases))
print('PASS: native existing and unsaved template filter node fixtures')

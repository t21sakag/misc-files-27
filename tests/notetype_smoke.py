from engine_smoke import Engine
from pathlib import Path
import base64
import json
import tempfile
from html.parser import HTMLParser

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'types')
    first = engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': first})
    schema['id'] = '0'; schema['name'] = 'Editable schema'
    tid = engine.call('NotetypesService.AddNotetype', schema)['id']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': tid})
    note = engine.call('NotesService.NewNote', {'ntid': tid})
    note['fields'] = ['original front', 'original back']
    nid = engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
    schema['fields'].append({'name': 'Extra', 'config': {'fontName': 'Arial', 'fontSize': 20}})
    engine.call('NotetypesService.UpdateNotetype', schema)
    assert engine.call('NotesService.GetNote', {'nid': nid})['fields'] == ['original front', 'original back', '']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': tid})
    schema['fields'][0]['name'] = 'RenamedFront'
    schema['fields'] = [schema['fields'][1], schema['fields'][0], schema['fields'][2]]
    schema['config']['css'] = '.card { color: blue; }'
    engine.call('NotetypesService.UpdateNotetype', schema)
    changed = engine.call('NotesService.GetNote', {'nid': nid})
    assert changed['fields'] == ['original back', 'original front', '']
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': tid})
    assert 'RenamedFront' in schema['templates'][0]['config']['qFormat']
    schema['fields'].pop()
    second = json.loads(json.dumps(schema['templates'][0]))
    second.pop('ord', None); second['name'] = 'Card 2'
    second['config']['qFormat'] = '{{' + schema['fields'][0]['name'] + '}}'
    schema['templates'].append(second)
    engine.call('NotetypesService.UpdateNotetype', schema)
    cards = engine.call('NotesService.CardsOfNote', {'nid': nid})['cids']
    assert len(cards) == 2
    schema = engine.call('NotetypesService.GetNotetype', {'ntid': tid})
    note = engine.call('NotesService.GetNote', {'nid': nid})
    preview = engine.call('CardRenderingService.RenderUncommittedCard', {'note': note, 'cardOrd': 0, 'template': schema['templates'][0], 'fillEmpty': True})
    assert 'original front' in ''.join(n.get('text', '') for n in preview['questionNodes'])
    schema['templates'].pop(0)
    engine.call('NotetypesService.UpdateNotetype', schema)
    assert len(engine.call('NotesService.CardsOfNote', {'nid': nid})['cids']) == 1
    legacy = engine.call('NotetypesService.GetStockNotetypeLegacy', {'kind': 'KIND_CLOZE'})
    value = json.loads(base64.b64decode(legacy['json']))
    value['name'] = 'Created cloze'; value['id'] = 0
    cloze_id = engine.call('NotetypesService.AddNotetypeLegacy', {'json': base64.b64encode(json.dumps(value).encode()).decode()})['id']
    assert engine.call('NotetypesService.GetNotetype', {'ntid': cloze_id})['config']['kind'] == 'KIND_CLOZE'
    draft = engine.call('NotesService.NewNote', {'ntid': cloze_id})
    draft['fields'] = ['{{c1::first}} and {{c3::third}}', 'Draft extra']
    assert sorted(engine.call('NotesService.ClozeNumbersInNote', draft)['numbers']) == [1, 3]
    cloze_schema = engine.call('NotetypesService.GetNotetype', {'ntid': cloze_id})
    rendered = engine.call('CardRenderingService.RenderUncommittedCard', {'note': draft, 'cardOrd': 2, 'template': cloze_schema['templates'][0], 'fillEmpty': True})
    question = ''.join(node.get('text', '') for node in rendered['questionNodes'])
    class VisibleText(HTMLParser):
        def __init__(self):
            super().__init__(); self.parts = []
        def handle_data(self, data):
            self.parts.append(data)
    visible = VisibleText(); visible.feed(question)
    assert ''.join(visible.parts) == 'first and [...]', question
    assert 'class="cloze"' in question and 'data-ordinal="3"' in question, question
    assert not engine.call('SearchService.SearchNotes', {'search': 'mid:' + cloze_id}).get('ids')
    engine.call('NotetypesService.RemoveNotetype', {'ntid': cloze_id})
    engine.close()
print('PASS: note type create/copy + field add/rename/reorder/delete migration + templates/cards + CSS + preview + stock types')

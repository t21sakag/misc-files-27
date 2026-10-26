from engine_smoke import Engine
from pathlib import Path
import base64
import tempfile

# Exercise the same collection operations invoked by the bundled mask editor.
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    image = root / 'occlusion.png'
    image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jwZkAAAAASUVORK5CYII='))
    engine = Engine(root / 'collection')
    data = engine.call('ImageOcclusionService.GetImageForOcclusion', {'path': str(image)})
    assert base64.b64decode(data['data']) == image.read_bytes()
    masks = '{{c1::image-occlusion:rect:left=.1:top=.1:width=.2:height=.3}}<br>{{c2::image-occlusion:ellipse:left=.4:top=.4:rx=.1:ry=.1}}'
    engine.call('ImageOcclusionService.AddImageOcclusionNote', {
        'imagePath': str(image), 'occlusions': masks, 'header': 'Diagram',
        'backExtra': 'Explanation', 'tags': ['diagram'],
    })
    notes = engine.call('SearchService.SearchNotes', {'search': 'tag:diagram'})['ids']
    assert len(notes) == 1
    nid = notes[0]
    cards = engine.call('NotesService.CardsOfNote', {'nid': nid})['cids']
    assert len(cards) == 2
    record = engine.call('ImageOcclusionService.GetImageOcclusionNote', {'noteId': nid})['note']
    assert record['header'] == 'Diagram' and len(record['occlusions']) == 2
    assert base64.b64decode(record['imageData']) == image.read_bytes()
    engine.call('ImageOcclusionService.UpdateImageOcclusionNote', {
        'noteId': nid, 'occlusions': masks.split('<br>')[0],
        'header': 'Updated', 'backExtra': 'Updated explanation', 'tags': ['updated-diagram'],
    })
    updated = engine.call('ImageOcclusionService.GetImageOcclusionNote', {'noteId': nid})['note']
    assert updated['header'] == 'Updated' and len(updated['occlusions']) == 1
    assert updated['tags'] == ['updated-diagram']
    for cid in cards:
        rendered = engine.call('CardRenderingService.RenderExistingCard', {'cardId': cid})
        assert 'image-occlusion' in str(rendered)
    engine.close()
print('PASS: image occlusion load + image/media persistence + multiple masks/cards + edit + native render')

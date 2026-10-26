from engine_smoke import Engine
from pathlib import Path
import base64
import tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'web')
    request = base64.b64encode(b'\x08\x01').decode()
    decoded = engine.call('_decode/get_deck_configs_for_update', {'data': request})
    assert decoded['did'] == '1'
    result = engine.call('_anki/get_deck_configs_for_update', {'data': request})
    assert len(base64.b64decode(result['data'])) > 20
    translated = engine.call('_anki/i18n_resources', {'data': ''})
    assert len(base64.b64decode(translated['data'])) > 100
    assert engine.call('_encode/ask_user', {'val': True})['data'] == 'CAE='
    graphs = engine.call('_anki/graphs', {'data': ''})
    assert graphs['data']
    engine.close()
print('PASS: generated binary Protobuf routes + request decode + response encode + deck options + graphs + translations')

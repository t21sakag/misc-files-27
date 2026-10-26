from engine_smoke import Engine
import sys
import tempfile
from pathlib import Path
import time
import urllib.request

endpoint = 'http://127.0.0.1:18891/'
for attempt in range(100):
    try:
        urllib.request.urlopen(endpoint + 'health', timeout=1).close()
        break
    except OSError:
        time.sleep(.1)
else:
    raise AssertionError('UI sync server unavailable')
with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory) / 'seed')
    options = engine.call('ImportExportService.GetImportAnkiPackagePresets')
    engine.call('ImportExportService.ImportAnkiPackage', {'packagePath': str(Path(sys.argv[2]).resolve()), 'options': options})
    auth = engine.call('SyncService.SyncLogin', {'username': 'fixture@example.test', 'password': 'fixture-password', 'endpoint': endpoint})
    result = engine.call('SyncService.SyncCollection', {'auth': auth, 'syncMedia': False})
    engine.call('SyncService.FullUploadOrDownload', {'auth': auth, 'upload': True, 'serverUsn': result.get('serverMediaUsn', 0)})
    for attempt in range(300):
        if not engine.call('SyncService.MediaSyncStatus').get('active'):
            break
        time.sleep(.1)
    else:
        raise AssertionError('Seed media upload did not finish')
    engine.close()

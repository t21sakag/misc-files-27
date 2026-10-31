"""Exercise the real batch runner's preflight, observer, identities and warning gate."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CASE = 'BrowserToolsFlowTests/testNotesPreviewUsesRepresentativesUntilMultipleRowsSelected'
with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary); tools = base/'tools'; tools.mkdir()
    products = base/'build/simulator/Build/Products'; products.mkdir(parents=True)
    (products/'tests.xctestrun').write_bytes(b'Fake compiled run; actual plist transfer is checked separately')
    fixture = products/'Runner.app/PlugIns/Tests.xctest/ReceivedFixtures/preview.apkg'
    fixture.parent.mkdir(parents=True)
    with zipfile.ZipFile(fixture, 'w') as archive:
        archive.writestr('collection.anki21b', b'Container only; actual package import has a native test')
    (base/'build/ui-batches.json').write_text(json.dumps({'batches': [[CASE]]}))
    (base/'build/project-settings.json').write_text(json.dumps({'targets': [
        {'target': 'StudyWidgets', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.fixture.widgets'}]}))
    (tools/'xcrun').write_text('''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
args=sys.argv[1:]
if args[:2]==['simctl','spawn']:
    Path('build/observer-started').write_text('ready')
    print('browser.selection.trace phase=all.enter rows=3 selected=0',flush=True)
    time.sleep(60)
elif args[:4]==['xcresulttool','get','test-results','summary']:
    mode=os.environ['BATCH_FAKE_MODE']
    summary={'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'runtimeWarnings':[]}
    if mode=='warning':summary['runtimeWarnings']=[{'message':'Synthetic warning'}]
    if mode=='missing-warning-field':summary.pop('runtimeWarnings')
    if mode=='failed':summary.update(passedTests=0,failedTests=1)
    if mode=='skipped':summary.update(passedTests=0,skippedTests=1)
    print(json.dumps(summary))
elif args[:4]==['xcresulttool','get','test-results','tests']:
    case=os.environ['BATCH_EXPECTED_CASE']
    if os.environ['BATCH_FAKE_MODE']=='wrong-identity':case='Missing/testWrong'
    print(json.dumps({'testNodes':[{'nodeType':'Test Case','nodeIdentifier':case+'()'}]}))
else:raise SystemExit('Unexpected xcrun command '+str(args))
''')
    (tools/'xcodebuild').write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
assert Path('build/observer-started').is_file(),'Observer must start before UI'
assert '-only-testing:AnkiPadUITests/'+os.environ['BATCH_EXPECTED_CASE'] in sys.argv
Path('build/ui-started').write_text('started')
raise SystemExit(65 if os.environ['BATCH_FAKE_MODE']=='failed' else 0)
''')
    for tool in tools.iterdir(): tool.chmod(0o755)
    environment = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'], BATCH_EXPECTED_CASE=CASE)
    command = [sys.executable, str(ROOT/'scripts/run-ui-batch.py'), '0', '11111111-1111-4111-8111-111111111111']
    def run(mode, success, ui_started=True):
        for name in ['ui-started','observer-started']:
            (base/'build'/name).unlink(missing_ok=True)
        result = subprocess.run(command, cwd=base, env=dict(environment,BATCH_FAKE_MODE=mode), capture_output=True,text=True,timeout=20)
        assert (result.returncode==0)==success,(mode,result.stdout,result.stderr)
        assert (base/'build/ui-started').exists()==ui_started
        return result
    run('passed', True)
    prerequisite=json.loads((base/'build/ui-prerequisites.json').read_text())
    assert prerequisite['preview_package_required'] and prerequisite['preview_package_valid']
    observer=json.loads((base/'build/widget-diagnostics/live-collection.json').read_text())
    assert observer['stream_running_before_test'] and observer['test_exit']==0
    for mode in ['warning','missing-warning-field','wrong-identity','skipped','failed']:
        run(mode,False)
    assert json.loads((base/'build/widget-diagnostics/live-collection.json').read_text())['test_exit']==65
    fixture.write_bytes(b'corrupt')
    run('passed',False,ui_started=False)
    fixture.unlink()
    run('passed',False,ui_started=False)
print('PASS: real batch runner validates bundled fixture before UI, starts live observer, preserves failures and rejects warnings/missing warning evidence/wrong identities/skips')

"""Exercise the real preflight transaction and its fail-closed UI entrypoint."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CASE = 'NotificationAuthorizationFlowTests/testActualNotificationAuthorizationAndScheduleReplacement'
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    tools = base / 'tools'; tools.mkdir()
    app = base / 'build/simulator/Build/Products/Debug-iphonesimulator/AnkiPad.app'
    app.mkdir(parents=True)
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.example.checks'}))
    container = base / 'container'; container.mkdir()
    (base / 'build/project-settings.json').write_text(json.dumps({'targets': [
        {'target': 'StudyWidgets', 'PRODUCT_BUNDLE_IDENTIFIER': 'org.example.checks.widgets'}]}))
    (app.parent.parent / 'checks.xctestrun').write_bytes(b'Synthetic products; plist transfer checked separately')
    (base / 'build/ui-batches.json').write_text(json.dumps({'batches': [[CASE]]}))
    (tools / 'xcrun').write_text('''#!/usr/bin/env python3
import json,os,sys,time
from pathlib import Path
a=sys.argv[1:]; mode=os.environ['PROBE_MODE']
with Path('calls.jsonl').open('a') as f: f.write(json.dumps(a)+'\\n')
if a[:2]==['simctl','spawn']:
 print('readiness observer started',flush=True); time.sleep(60)
elif a[:2]==['simctl','install']:
 if mode=='install-failure':sys.exit(17)
elif a[:2]==['simctl','get_app_container']:
 if mode=='container-failure':sys.exit(20)
 if not Path('launched-marker').exists():sys.exit(21)
 print(os.environ['PROBE_CONTAINER'])
elif a[:2]==['simctl','launch']:
 assert a[-1]=='--uitest-notification-readiness'
 if mode=='launch-failure':sys.exit(18)
 Path('launched-marker').write_text('started')
 namespace=os.environ['SIMCTL_CHILD_ANKIPAD_UI_TEST_NAMESPACE']
 p=Path(os.environ['PROBE_CONTAINER'])/'Library/Application Support/UITests'/namespace/'notification-service.json'
 p.parent.mkdir(parents=True)
 v={'version':1,'namespace':namespace,'bundle':'org.example.checks','phase':'complete','authorizationStatus':0,'pendingCount':0}
 if mode=='denied':v['authorizationStatus']=1
 if mode=='authorized':v['authorizationStatus']=2
 if mode=='wrong-namespace':v['namespace']='stale'
 if mode=='wrong-bundle':v['bundle']='org.other'
 if mode=='wrong-version':v['version']=2
 if mode=='unknown-phase':v['phase']='invented'
 if mode=='bad-status':v['authorizationStatus']=True
 if mode=='bad-pending':v['pendingCount']=-1
 if mode=='waiting':v['phase']='notificationSettings'
 if mode=='oversized':v['noise']='x'*5000
 if mode!='missing':p.write_text(json.dumps(v))
elif a[:2]==['simctl','terminate']:
 if mode=='terminate-failure':sys.exit(19)
elif a[:4]==['xcresulttool','get','test-results','summary']:
 print(json.dumps({'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'runtimeWarnings':[]}))
elif a[:4]==['xcresulttool','get','test-results','tests']:
 print(json.dumps({'testNodes':[{'nodeType':'Test Case','nodeIdentifier':os.environ['PROBE_CASE']+'()'}]}))
else:raise SystemExit('Unexpected OS command '+str(a))
''')
    (tools / 'xcodebuild').write_text('''#!/usr/bin/env python3
import json
from pathlib import Path
r=json.loads(Path('build/notification-preflight.json').read_text())
assert r['ready'] and r['terminated']
assert r['permission_requested'] is False and r['requests_mutated'] is False
Path('build/ui-started').write_text('yes')
''')
    for path in tools.iterdir(): path.chmod(0o755)
    env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'],
               PROBE_CONTAINER=str(container), PROBE_CASE=CASE)
    command = [sys.executable, str(ROOT/'scripts/notification-preflight.py'),
               '--simulator', '11111111-1111-4111-8111-111111111111', '--app', str(app), '--timeout', '0.1']
    for mode in ['ready','denied','authorized','wrong-namespace','wrong-bundle','wrong-version',
                 'unknown-phase','bad-status','bad-pending','waiting','missing','oversized',
                 'install-failure','launch-failure','container-failure','terminate-failure']:
        output = base/'build/notification-preflight.json'; output.unlink(missing_ok=True)
        (base/'launched-marker').unlink(missing_ok=True)
        result = subprocess.run(command, cwd=base, env=dict(env,PROBE_MODE=mode), capture_output=True,text=True,timeout=5)
        expected = mode in ('ready','denied','authorized')
        assert (result.returncode==0)==expected,(mode,result.stdout,result.stderr)
        report=json.loads(output.read_text())
        assert report['ready']==expected, (mode,report)
        assert report['permission_requested'] is False and report['requests_mutated'] is False
        if mode=='waiting':assert report['native']['phase']=='notificationSettings'
        if mode not in ('install-failure','launch-failure','terminate-failure'):assert report['terminated']
        operations=[item['operation'] for item in report['commands']]
        if mode not in ('install-failure','launch-failure'):
            assert operations[:3]==['install','launch','get_app_container'], report
        if mode=='container-failure':
            assert report['failure_phase']=='get_app_container' and report['terminated'], report
        if mode=='launch-failure':
            assert report['failure_phase']=='launch' and 'terminate' in operations, report
    # A real subprocess timeout has byte output and no return code. Preserve
    # its phase/output and clean up the already launched readiness process.
    spec = importlib.util.spec_from_file_location('notification_preflight', ROOT/'scripts/notification-preflight.py')
    preflight = importlib.util.module_from_spec(spec); spec.loader.exec_module(preflight)
    def container_timeout(command, **kwargs):
        if command[2] == 'get_app_container':
            raise subprocess.TimeoutExpired(command, 30, output=b'x'*3000, stderr=b'container service stalled')
        return subprocess.CompletedProcess(command, 0, stdout='', stderr='')
    timeout_output = base/'timeout-report.json'
    with patch.object(preflight.subprocess, 'run', side_effect=container_timeout):
        try:
            preflight.run('11111111-1111-4111-8111-111111111111', app, timeout_output)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise AssertionError('Container timeout must fail the preflight')
    timeout_report = json.loads(timeout_output.read_text())
    assert not timeout_report['ready'] and timeout_report['terminated'], timeout_report
    assert timeout_report['failure_phase'] == 'get_app_container', timeout_report
    failed_command = timeout_report['commands'][2]
    assert failed_command['error_kind'] == 'TimeoutExpired', failed_command
    assert len(failed_command['stdout']) == 2048 and failed_command['stderr'] == 'container service stalled'
    assert 'return_code' not in failed_command and failed_command['elapsed_seconds'] >= 0
    # Execute the real consumer: missing service identity fails before XCTest,
    # while a valid read-only OS reply permits the unmodified xctestrun path.
    runner=[sys.executable,str(ROOT/'scripts/run-ui-batch.py'),'0','11111111-1111-4111-8111-111111111111']
    for mode in ('wrong-bundle','ready'):
        marker=base/'build/ui-started';marker.unlink(missing_ok=True)
        (base/'launched-marker').unlink(missing_ok=True)
        result=subprocess.run(runner,cwd=base,env=dict(env,PROBE_MODE=mode),capture_output=True,text=True,timeout=20)
        assert (result.returncode==0)==(mode=='ready'),(mode,result.stdout,result.stderr)
        assert marker.exists()==(mode=='ready')
        observer=json.loads((base/'build/notification-preflight-diagnostics/live-collection.json').read_text())
        assert observer['stream_running_before_test']
    calls=[json.loads(line) for line in (base/'calls.jsonl').read_text().splitlines()]
    assert not any('privacy' in call or 'push' in call for call in calls)
print('PASS: real read-only preflight rejects stale/corrupt/unresponsive OS replies and cleanup failures; consumer starts XCTest only after valid response, without requiring or granting permission')

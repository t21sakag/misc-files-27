#!/usr/bin/env python3
"""Exercise log lifetime, bounded output, shutdown collection and exit handling."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('diagnostics', ROOT/'scripts/run-ui-with-diagnostics.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    executable = base/'xcrun'
    executable.write_text('''#!/usr/bin/env python3
import os, sys, time
from pathlib import Path
if 'stream' not in sys.argv:
    print('Device is not booted', flush=True)
    raise SystemExit(149)
Path(os.environ['PROBE_STARTED']).write_text('started')
print('launch', flush=True)
print('*** Assertion failure earliest-focus-fixture', flush=True)
print('usernotificationsd: Source is not authorized, UNErrorDomain Code=1', flush=True)
print('reminder.save.trace OS add failed; domain=UNErrorDomain; code=2003', flush=True)
print('ui.publication.trace account=server.binding proposed=Optional(true) state=server=false;busy=false;responder=none;secure=false', flush=True)
if os.environ.get('LARGE_LOG'):
    sys.stdout.buffer.write(b'x' * (9 * 1024 * 1024)); sys.stdout.buffer.flush()
    print('', flush=True)
if os.environ.get('MANY_CRITICAL'):
    for index in range(2000): print('*** Assertion failure event-' + str(index) + ' ' + ('y' * 100), flush=True)
assert any('browser.options.trace' in value for value in sys.argv)
assert any('audio.playback.trace' in value and 'AVAudioSession_iOS.mm' in value and 'SessionCore.mm' in value for value in sys.argv)
assert any('reminder.save.trace' in value and 'typing.focus.trace' in value and 'usernotificationsd' in value for value in sys.argv)
assert any('browser.selection.trace' in value for value in sys.argv)
assert any('ui.publication.trace' in value for value in sys.argv)
assert any('process == "SpringBoard"' in value and 'CONTAINS[c] "notification"' in value and 'CONTAINS[c] "source"' in value for value in sys.argv)
assert any('eventMessage CONTAINS "com.localtools.studyclient"' in value for value in sys.argv)
assert any('process == "AnkiPad"' in value and '_UIFocusContainerGuide' in value and 'Terminating app due to uncaught exception' in value for value in sys.argv)
print('*** Terminating app due to uncaught exception NSInvalidArgumentException, reason: fixture focus reason', flush=True)
print('browser.options.trace phase=load.end loaded=1', flush=True)
print('browser.selection.trace phase=all.enter rows=3 selected=0', flush=True)
print('WidgetProbe timeline.request', flush=True)
Path(os.environ['PROBE_EMITTED']).write_text('ready')
while True: time.sleep(1)
''')
    executable.chmod(0o755)
    previous = os.environ.copy()
    try:
        os.environ['PATH'] = str(base)+os.pathsep+os.environ['PATH']
        os.environ['PROBE_STARTED'] = str(base/'started')
        os.environ['PROBE_EMITTED'] = str(base/'emitted')
        os.environ['LARGE_LOG'] = '1'
        simulator = str(uuid.uuid4()).upper()
        bundle = 'com.localtools.studyclient.widgets'
        command = [sys.executable, '-c',
                   'import os,time\nfrom pathlib import Path\n'
                   'assert Path(os.environ["PROBE_STARTED"]).is_file()\n'
                   'deadline=time.monotonic()+20\n'
                   'while not Path(os.environ["PROBE_EMITTED"]).is_file():\n'
                   ' assert time.monotonic()<deadline,"Observer fixture did not finish emitting"\n'
                   ' time.sleep(.01)\n'
                   'raise SystemExit(7)']
        output = base/'live'
        assert module.run(simulator, bundle, output, command) == 7
        report = json.loads((output/'live-collection.json').read_text())
        assert report['test_exit'] == 7 and report['stream_running_before_test']
        assert report['truncated'] and report['bytes_saved'] <= module.LIMIT
        assert b'WidgetProbe timeline.request' in (output/'live.log').read_bytes()
        assert b'browser.options.trace phase=load.end' in (output/'live.log').read_bytes()
        assert b'browser.selection.trace phase=all.enter' in (output/'live.log').read_bytes()
        assert b'fixture focus reason' in (output/'live.log').read_bytes()
        critical = (output/'critical.log').read_bytes()
        assert b'earliest-focus-fixture' not in (output/'live.log').read_bytes()
        assert b'earliest-focus-fixture' in critical and b'fixture focus reason' in critical
        assert b'Source is not authorized' in critical
        assert b'domain=UNErrorDomain; code=2003' in critical
        assert b'account=server.binding' in critical
        assert not report['critical_truncated'] and report['critical_bytes_saved'] == len(critical)
        assert report['line_buffer_bytes_dropped'] > 0
        os.environ.pop('LARGE_LOG')
        os.environ['MANY_CRITICAL'] = '1'
        (base/'emitted').unlink()
        assert module.run(simulator, bundle, base/'many', command) == 7
        many = json.loads((base/'many/live-collection.json').read_text())
        critical = (base/'many/critical.log').read_bytes()
        assert many['critical_truncated'] and len(critical) <= module.CRITICAL_LIMIT
        assert b'earliest-focus-fixture' in critical and b'event-1999 ' not in critical
        os.environ.pop('MANY_CRITICAL')
        # An observer failure must not replace a successful UI command's result.
        executable.write_text('#!/usr/bin/env python3\nraise SystemExit(149)\n')
        assert module.run(simulator, bundle, base/'unavailable', [sys.executable, '-c', 'pass']) == 0
        assert json.loads((base/'unavailable/live-collection.json').read_text())['log_exit'] == 149
        # Post-test probe collection does not depend on a booted simulator.
        home = base/'home'
        data = home/'Library/Developer/CoreSimulator/Devices'/simulator/'data'
        container = data/'Containers/Data/PluginKitPlugin'/str(uuid.uuid4())
        container.mkdir(parents=True)
        (container/'.com.apple.mobile_container_manager.metadata.plist').write_bytes(plistlib.dumps({'MCMMetadataIdentifier': bundle}))
        probe = container/'Library/Application Support/widget-probe.json'
        probe.parent.mkdir(parents=True)
        probe.write_text('[{"phase":"timeline.request"}]')
        # A different extension's diagnostic must never be collected.
        other = container.parent/str(uuid.uuid4())
        other.mkdir()
        (other/'.com.apple.mobile_container_manager.metadata.plist').write_bytes(plistlib.dumps({'MCMMetadataIdentifier': 'unrelated.widgets'}))
        settings = base/'settings.json'
        settings.write_text(json.dumps({'targets': [{'target': 'StudyWidgets', 'PRODUCT_BUNDLE_IDENTIFIER': bundle}]}))
        destination = base/'collected'
        result = subprocess.run([sys.executable, str(ROOT/'scripts/collect-widget-diagnostics.py'), '--simulator', simulator,
            '--settings', str(settings), '--output', str(destination)], env=dict(os.environ, HOME=str(home)), capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        collection = json.loads((destination/'collection.json').read_text())
        assert collection['container_found'] and collection['probe_found'] and collection['log_exit'] == 149
        assert (destination/'widget-probe.json').read_bytes() == probe.read_bytes()
        # Some simulator extension processes use the device home, with the
        # bundle-prefixed filename. Collect only this device and exact bundle.
        content = probe.read_bytes(); probe.unlink()
        shared_probe = data/'Library/Application Support'/(bundle+'-widget-probe.json')
        shared_probe.parent.mkdir(parents=True)
        shared_probe.write_bytes(content)
        result = subprocess.run([sys.executable, str(ROOT/'scripts/collect-widget-diagnostics.py'), '--simulator', simulator,
            '--settings', str(settings), '--output', str(destination)], env=dict(os.environ, HOME=str(home)), capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert json.loads((destination/'collection.json').read_text())['probe_location'] == 'owned-device-home'
        assert (destination/'widget-probe.json').read_bytes() == content
    finally:
        os.environ.clear()
        os.environ.update(previous)
print('PASS: live log before UI; bounded capture; child exit preserved; owned persistent probe collected after shutdown')

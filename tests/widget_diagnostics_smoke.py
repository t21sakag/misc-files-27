#!/usr/bin/env python3
"""Exercise log lifetime, bounded output, shutdown collection and exit handling."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('diagnostics', ROOT/'scripts/run-ui-with-diagnostics.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    executable = base/'xcrun'
    executable.write_text('''#!/usr/bin/env python3
import os, sys, time, signal
from pathlib import Path
if 'recordVideo' in sys.argv:
    Path(sys.argv[-1]).write_bytes(b'Native display fixture')
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    while True: time.sleep(1)
if 'stream' not in sys.argv:
    print('Device is not booted', flush=True)
    raise SystemExit(149)
Path(os.environ['PROBE_STARTED']).write_text(str(os.getpid()))
print('launch', flush=True)
print('*** Assertion failure earliest-focus-fixture', flush=True)
print('usernotificationsd: Source is not authorized, UNErrorDomain Code=1', flush=True)
print('reminder.save.trace await authorization settings', flush=True)
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
        video = json.loads((output/'screen-recording.json').read_text())
        assert video['simulator'] == simulator and video['closed'] and video['ready']
        assert video['native_exit'] == 0 and video['bytes_saved'] > 0
        limited_command = [sys.executable, '-c', 'import time;time.sleep(.8);raise SystemExit(7)']
        assert module.run(simulator, bundle, base/'limited', limited_command, screen_seconds=.3) == 7
        limited = json.loads((base/'limited/screen-recording.json').read_text())
        assert limited['duration_limited'] and limited['closed'] and limited['native_exit'] == 0
        assert report['truncated'] and report['bytes_saved'] <= module.LIMIT
        assert b'WidgetProbe timeline.request' in (output/'live.log').read_bytes()
        assert b'browser.options.trace phase=load.end' in (output/'live.log').read_bytes()
        assert b'browser.selection.trace phase=all.enter' in (output/'live.log').read_bytes()
        assert b'fixture focus reason' in (output/'live.log').read_bytes()
        critical = (output/'critical.log').read_bytes()
        assert b'earliest-focus-fixture' not in (output/'live.log').read_bytes()
        assert b'earliest-focus-fixture' in critical and b'fixture focus reason' in critical
        assert b'Source is not authorized' in critical
        assert b'await authorization settings' in critical
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
        # SIGKILL skips the wrapper's finally block. First evidence must
        # already be on disk, with metadata explicitly marked incomplete.
        interrupted = base/'interrupted'
        child_pid = base/'child.pid'
        (base/'started').unlink()
        child_command = [sys.executable, '-c', 'import os,time;from pathlib import Path;'
                         f'Path({str(child_pid)!r}).write_text(str(os.getpid()));time.sleep(60)']
        wrapper_source = (
            'import importlib.util;from pathlib import Path;'
            f'spec=importlib.util.spec_from_file_location("observer",{str(ROOT/"scripts/run-ui-with-diagnostics.py")!r});'
            'module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);'
            f'raise SystemExit(module.run({simulator!r},{bundle!r},Path({str(interrupted)!r}),'
            f'{child_command!r},screen_seconds=.5))')
        wrapper = subprocess.Popen([sys.executable, '-c', wrapper_source])
        try:
            deadline = time.monotonic() + 20
            evidence = interrupted/'critical.log'
            while not (child_pid.exists() and evidence.exists()
                       and b'fixture focus reason' in evidence.read_bytes()):
                assert time.monotonic() < deadline, 'Live critical evidence was not persisted'
                assert wrapper.poll() is None, 'Wrapper exited before interruption test'
                time.sleep(.01)
            wrapper.kill()
            wrapper.wait(timeout=5)
            assert b'earliest-focus-fixture' in evidence.read_bytes()
            assert len(evidence.read_bytes()) <= module.CRITICAL_LIMIT
            assert json.loads((interrupted/'live-collection.json').read_text())['complete'] is False
            video_state = interrupted/'screen-recording.json'
            deadline = time.monotonic() + 5
            while not json.loads(video_state.read_text())['closed']:
                assert time.monotonic() < deadline, 'Recorder lost its independent wall-clock limit'
                time.sleep(.01)
            video = json.loads(video_state.read_text())
            assert video['duration_limited'] and video['native_exit'] == 0
        finally:
            if wrapper.poll() is None:
                wrapper.kill(); wrapper.wait(timeout=5)
            video_state = interrupted/'screen-recording.json'
            if video_state.exists():
                video = json.loads(video_state.read_text())
                try:
                    os.killpg(video['supervisor_pid'], signal.SIGKILL)
                except ProcessLookupError:
                    pass
            for pid_file in (base/'started', child_pid):
                if pid_file.exists():
                    try:
                        os.killpg(int(pid_file.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
        # An observer failure must not replace a successful UI command's result.
        executable.write_text('#!/usr/bin/env python3\nraise SystemExit(149)\n')
        assert module.run(simulator, bundle, base/'unavailable', [sys.executable, '-c', 'pass']) == 0
        assert json.loads((base/'unavailable/live-collection.json').read_text())['log_exit'] == 149
        unavailable_video = json.loads((base/'unavailable/screen-recording.json').read_text())
        assert unavailable_video['native_exit'] == 149 and not unavailable_video['ready']
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

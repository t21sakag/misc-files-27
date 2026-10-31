"""Execute the workflow's actual selected-UI shell with fake Apple commands.

An observer unit test does not establish that a particular suite uses it.
Keep the real workflow entrypoint, worker selector and observer in this check.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import uuid

ROOT = Path(__file__).resolve().parents[1]
workflow = (ROOT / '.github/workflows/ipa.yml').read_text()
step = workflow.split('      - name: Execute selected UI cases without rebuilding\n', 1)[1]
body = step.split('        run: |\n', 1)[1].split('      - name:', 1)[0]
shell = textwrap.dedent(body)
summary_step = workflow.split('      - name: Export structured UI failures and timing\n', 1)[1].split('      - name:', 1)[0]
assert 'build/test-summary.json --reject-runtime-warnings' in summary_step

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    for directory in ('scripts', 'ios', 'build', 'bin'):
        (base / directory).mkdir()
    for name in ('select-ui-workers.py', 'run-ui-with-diagnostics.py'):
        shutil.copy2(ROOT / 'scripts' / name, base / 'scripts' / name)
    (base / 'build/project-settings.json').write_text(json.dumps({'targets': [
        {'target': 'StudyWidgets', 'PRODUCT_BUNDLE_IDENTIFIER': 'org.example.study.widgets'}]}))
    xcrun = base / 'bin/xcrun'
    xcrun.write_text('''#!/usr/bin/env python3
import os, sys, time
from pathlib import Path
if 'stream' in sys.argv:
    Path(os.environ['LIVE_STARTED']).write_text('yes')
    print('observer ready', flush=True)
    while True: time.sleep(1)
else:
    print('{"devices":{}}')
''')
    xcode = base / 'bin/xcodebuild'
    xcode.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
assert Path(os.environ['LIVE_STARTED']).is_file(), 'UI began without the live observer'
Path(os.environ['XCODE_ARGS']).write_text(json.dumps(sys.argv[1:]))
raise SystemExit(23)
''')
    xcrun.chmod(0o755)
    xcode.chmod(0o755)
    for suite in ('notification-baseline', 'typing-focus', 'browser-preview-order', 'widget-gallery'):
        selection = subprocess.check_output([sys.executable, str(ROOT / 'scripts/select-ui-tests.py'), suite, 'ui'], text=True)
        (base / 'build/ui-test-arguments.txt').write_text(selection)
        started = base / ('started-' + suite)
        arguments = base / ('arguments-' + suite)
        env = dict(os.environ, PATH=str(base / 'bin') + os.pathsep + os.environ['PATH'],
                   UI_SUITE=suite, SIMULATOR_ID=str(uuid.uuid4()).upper(),
                   LIVE_STARTED=str(started), XCODE_ARGS=str(arguments),
                   GITHUB_SHA='a' * 40, GITHUB_RUN_NUMBER='1')
        result = subprocess.run(['bash', '-e', '-c', shell], cwd=base, env=env,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 23, (suite, result.stdout, result.stderr)
        report = json.loads((base / 'build/widget-diagnostics/live-collection.json').read_text())
        assert report['stream_running_before_test'] and report['test_exit'] == 23, (suite, report)
        args = json.loads(arguments.read_text())
        assert all(line in args for line in selection.splitlines()), (suite, args)
        assert args[args.index('-parallel-testing-enabled') + 1] == 'NO'
    for warning, should_fail in (([], False), ([{'message': 'real warning'}], True), (None, True)):
        summary = {'result': 'Passed', 'passedTests': 1, 'failedTests': 0}
        if warning is not None:
            summary['runtimeWarnings'] = warning
        path = base / 'summary.json'
        path.write_text(json.dumps(summary))
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/summarize-ui-results.py'),
                                 str(path), '--reject-runtime-warnings'], capture_output=True, text=True)
        assert (result.returncode != 0) == should_fail, (warning, result.stdout, result.stderr)

print('PASS: actual selected-UI workflow starts bounded observer for notification/focus/browser/widget; preserves UI exit and selections; rejects warnings or missing warning evidence')

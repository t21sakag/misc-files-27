#!/usr/bin/env python3
"""Capture owned simulator diagnostics while the selected UI command runs.

Xcode may shut down the simulator before a post-test log-show command can run.
The observer never boots a device, retries a test, or changes its exit status.
Owned log and screen subprocesses are stopped at exit. The log retains 8 MiB;
the independent display recorder has a 30-minute wall-clock limit.
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import threading
import time
import uuid

LIMIT = 8 * 1024 * 1024
CRITICAL_LIMIT = 64 * 1024
LINE_LIMIT = 16 * 1024
CRITICAL_MARKERS = (b'*** Assertion failure', b'*** Terminating app due to uncaught exception',
                    b'not authorized', b'UNErrorDomain Code=1', b'reminder.save.trace ', b'browser.undo.trace ', b'browser.input.trace ', b'incoming.file.trace ', b'ui.publication.trace account=server.binding')


def run(simulator, bundle, output, command, screen_seconds=1800):
    simulator = str(uuid.UUID(simulator)).upper()
    if not re.fullmatch(r'[A-Za-z0-9.-]+', bundle) or not bundle.endswith('.widgets'):
        raise ValueError('Invalid widget bundle identifier')
    output.mkdir(parents=True, exist_ok=True)
    report = {'simulator': simulator, 'log_exit': None, 'bytes_seen': 0, 'bytes_saved': 0,
              'truncated': False, 'test_exit': None, 'complete': False}
    # Runner cancellation can kill this wrapper before finally executes.
    # Persist the bounded first evidence as it arrives, not only at exit.
    (output/'critical.log').write_bytes(b'')
    (output/'live-collection.json').write_text(json.dumps(report, indent=2)+'\n')
    chunks = deque()
    critical_lines = []
    critical_size = 0
    size = 0
    ready = threading.Event()
    observer = None
    reader = None
    child = None
    screen_recorder = None
    old_handlers = {}

    def keep_critical(line):
        nonlocal critical_size
        if not any(marker.lower() in line.lower() for marker in CRITICAL_MARKERS):
            return
        report['critical_bytes_seen'] = report.get('critical_bytes_seen', 0) + len(line)
        # Preserve the first failure even when later successful cases flood
        # the rolling live log. This separate capture is also bounded.
        if critical_size + len(line) <= CRITICAL_LIMIT:
            critical_lines.append(line)
            critical_size += len(line)
            with (output/'critical.log').open('ab') as destination:
                destination.write(line)

    def drain():
        nonlocal size
        pending = b''
        while data := os.read(observer.stdout.fileno(), 4096):
            ready.set()
            report['bytes_seen'] += len(data)
            chunks.append(data)
            size += len(data)
            while size > LIMIT:
                size -= len(chunks.popleft())
            pending += data
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                keep_critical(line + b'\n')
            # Simulator logs can contain very long unrelated lines. Never
            # turn the extra evidence buffer into an unbounded allocation.
            if len(pending) > LINE_LIMIT:
                report['line_buffer_bytes_dropped'] = report.get('line_buffer_bytes_dropped', 0) + len(pending) - LINE_LIMIT
                pending = pending[-LINE_LIMIT:]
        if pending:
            keep_critical(pending)
        ready.set()

    def forward(signum, _frame):
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signum)
        else:
            raise KeyboardInterrupt

    try:
        predicate = 'process == "StudyWidgets" OR eventMessage CONTAINS ' + json.dumps(bundle.removesuffix('.widgets')) + ' OR (process == "SpringBoard" AND (eventMessage CONTAINS[c] "notification" OR eventMessage CONTAINS[c] "source")) OR eventMessage BEGINSWITH "browser.options.trace " OR eventMessage BEGINSWITH "browser.selection.trace " OR eventMessage BEGINSWITH "ui.publication.trace " OR eventMessage BEGINSWITH "audio.playback.trace " OR eventMessage CONTAINS "AVAudioSession_iOS.mm" OR eventMessage CONTAINS "SessionCore.mm" OR eventMessage BEGINSWITH "typing.focus.trace " OR eventMessage BEGINSWITH "reminder.save.trace " OR process == "usernotificationsd" OR process == "AnkiPad" OR eventMessage CONTAINS "_UIFocusContainerGuide" OR eventMessage CONTAINS "Terminating app due to uncaught exception"'
        try:
            observer = subprocess.Popen(['xcrun', 'simctl', 'spawn', simulator, 'log', 'stream',
                '--style', 'compact', '--level', 'info', '--predicate', predicate],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
            reader = threading.Thread(target=drain, daemon=True)
            reader.start()
            ready.wait(timeout=3)
            report['stream_running_before_test'] = observer.poll() is None
        except OSError as error:
            report['observer_error'] = str(error)
        try:
            # A separate supervisor retains its wall-clock bound even if this
            # wrapper is killed before finally. It records the simulator, so
            # external URL launches do not leave video tied to an old app PID.
            screen_metadata = output/'screen-recording.json'
            screen_metadata.unlink(missing_ok=True)
            screen_recorder = subprocess.Popen([sys.executable,
                str(Path(__file__).with_name('record-ui-screen.py')),
                '--simulator', simulator, '--output', str(output), '--seconds', str(screen_seconds)],
                start_new_session=True)
            report['screen_recorder_pid'] = screen_recorder.pid
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and screen_recorder.poll() is None:
                if screen_metadata.exists():
                    state = json.loads(screen_metadata.read_text())
                    if state['native_pid'] is not None or state['closed']:
                        break
                time.sleep(0.05)
            report['screen_recorder_metadata_ready'] = screen_metadata.exists()
            (output/'live-collection.json').write_text(json.dumps(report, indent=2)+'\n')
        except OSError as error:
            report['screen_recorder_error'] = str(error)
        for signum in (signal.SIGINT, signal.SIGTERM):
            old_handlers[signum] = signal.signal(signum, forward)
        child = subprocess.Popen(command, start_new_session=True)
        report['test_exit'] = child.wait()
        return report['test_exit'] if report['test_exit'] >= 0 else 128 - report['test_exit']
    finally:
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
        if screen_recorder is not None:
            if screen_recorder.poll() is None:
                screen_recorder.terminate()
            try:
                screen_recorder.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(screen_recorder.pid, signal.SIGKILL)
                screen_recorder.wait(timeout=5)
            report['screen_recorder_exit'] = screen_recorder.returncode
        if observer is not None:
            if observer.poll() is None:
                try:
                    os.killpg(observer.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            try:
                observer.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(observer.pid, signal.SIGKILL)
                observer.wait(timeout=5)
            reader.join(timeout=5)
            report['log_exit'] = observer.returncode
        log = b''.join(chunks)
        report['bytes_saved'] = len(log)
        report['truncated'] = report['bytes_seen'] > len(log)
        (output/'live.log').write_bytes(log)
        report['critical_bytes_saved'] = critical_size
        report['critical_truncated'] = report.get('critical_bytes_seen', 0) > critical_size
        (output/'critical.log').write_bytes(b''.join(critical_lines))
        report['complete'] = True
        (output/'live-collection.json').write_text(json.dumps(report, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--settings', type=Path, default=Path('build/project-settings.json'))
    parser.add_argument('--output', type=Path, default=Path('build/widget-diagnostics'))
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('A UI command is required after --')
    settings = json.loads(args.settings.read_text())
    bundle = next(target['PRODUCT_BUNDLE_IDENTIFIER'] for target in settings['targets'] if target['target'] == 'StudyWidgets')
    return run(args.simulator, bundle, args.output, command)


if __name__ == '__main__':
    raise SystemExit(main())

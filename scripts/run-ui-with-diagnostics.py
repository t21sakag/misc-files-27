#!/usr/bin/env python3
"""Capture the owned simulator's widget log while the selected UI command runs.

Xcode may shut down the simulator before a post-test log-show command can run.
The observer never boots a device, retries a test, or changes its exit status.
Only its own log subprocess is terminated; output is bounded to the last 8 MiB.
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import uuid

LIMIT = 8 * 1024 * 1024


def run(simulator, bundle, output, command):
    simulator = str(uuid.UUID(simulator)).upper()
    if not re.fullmatch(r'[A-Za-z0-9.-]+', bundle) or not bundle.endswith('.widgets'):
        raise ValueError('Invalid widget bundle identifier')
    output.mkdir(parents=True, exist_ok=True)
    report = {'simulator': simulator, 'log_exit': None, 'bytes_seen': 0, 'bytes_saved': 0,
              'truncated': False, 'test_exit': None}
    chunks = deque()
    size = 0
    ready = threading.Event()
    observer = None
    reader = None
    child = None
    old_handlers = {}

    def drain():
        nonlocal size
        while data := os.read(observer.stdout.fileno(), 4096):
            ready.set()
            report['bytes_seen'] += len(data)
            chunks.append(data)
            size += len(data)
            while size > LIMIT:
                size -= len(chunks.popleft())
        ready.set()

    def forward(signum, _frame):
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signum)
        else:
            raise KeyboardInterrupt

    try:
        predicate = 'process == "StudyWidgets" OR eventMessage CONTAINS ' + json.dumps(bundle) + ' OR eventMessage BEGINSWITH "browser.options.trace "'
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
        for signum in (signal.SIGINT, signal.SIGTERM):
            old_handlers[signum] = signal.signal(signum, forward)
        child = subprocess.Popen(command, start_new_session=True)
        report['test_exit'] = child.wait()
        return report['test_exit'] if report['test_exit'] >= 0 else 128 - report['test_exit']
    finally:
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
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

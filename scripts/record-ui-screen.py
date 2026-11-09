#!/usr/bin/env python3
"""Record the owned simulator display across application process changes."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import uuid


def record(simulator, output, seconds):
    simulator = str(uuid.UUID(simulator)).upper()
    if not 0 < seconds <= 1800:
        raise ValueError('Screen recording limit must be in (0, 1800] seconds')
    output.mkdir(parents=True, exist_ok=True)
    movie = output/'native-screen.mp4'
    metadata = output/'screen-recording.json'
    report = {'simulator': simulator, 'supervisor_pid': os.getpid(), 'native_pid': None,
              'seconds_limit': seconds, 'duration_limited': False, 'closed': False,
              'native_exit': None, 'bytes_saved': 0, 'ready': False,
              'started_at_epoch': time.time(), 'ready_at_epoch': None}
    native = None
    stopping = False

    def persist():
        temporary = metadata.with_suffix('.tmp')
        temporary.write_text(json.dumps(report, indent=2)+'\n')
        temporary.replace(metadata)

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True
        if native is not None and native.poll() is None:
            native.send_signal(signal.SIGINT)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    persist()
    try:
        deadline = time.monotonic() + seconds
        movie.unlink(missing_ok=True)
        with (output/'screen-recording.log').open('wb') as log:
            native = subprocess.Popen(['xcrun', 'simctl', 'io', simulator,
                'recordVideo', '--force', str(movie)], stdout=log, stderr=subprocess.STDOUT)
            if stopping:
                stop(None, None)
            startup_deadline = min(deadline, time.monotonic() + 3)
            while native.poll() is None and time.monotonic() < startup_deadline:
                if movie.exists() and movie.stat().st_size > 0:
                    report['ready'] = True
                    report['ready_at_epoch'] = time.time()
                    break
                time.sleep(0.05)
            report['native_pid'] = native.pid
            persist()
            try:
                native.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                report['duration_limited'] = True
                stop(None, None)
                try:
                    native.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    native.kill()
                    native.wait(timeout=5)
            report['native_exit'] = native.returncode
    except OSError as error:
        report['error'] = str(error)
    finally:
        report['closed'] = True
        report['closed_at_epoch'] = time.time()
        report['bytes_saved'] = movie.stat().st_size if movie.exists() else 0
        persist()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--seconds', type=float, default=1800)
    args = parser.parse_args()
    record(args.simulator, args.output, args.seconds)

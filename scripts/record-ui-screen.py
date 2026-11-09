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
              'started_at_epoch': time.time(), 'ready_at_epoch': None, 'ready_source': None}
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
        log_path = output/'screen-recording.log'
        with log_path.open('wb') as log:
            native = subprocess.Popen(['xcrun', 'simctl', 'io', simulator,
                'recordVideo', '--force', str(movie)], stdout=log, stderr=subprocess.STDOUT)
            if stopping:
                stop(None, None)
            report['native_pid'] = native.pid
            persist()
            while native.poll() is None:
                # Startup can outlast the wrapper's readiness budget. Keep
                # observing its acknowledgement until this recorder exits.
                if not report['ready']:
                    acknowledged = b'Recording started' in log_path.read_bytes()
                    if acknowledged or (movie.exists() and movie.stat().st_size > 0):
                        report['ready'] = True
                        report['ready_at_epoch'] = time.time()
                        report['ready_source'] = 'native-log' if acknowledged else 'movie-file'
                        persist()
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    report['duration_limited'] = True
                    stop(None, None)
                    try:
                        native.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        native.kill()
                        native.wait(timeout=5)
                    break
                try:
                    native.wait(timeout=min(0.05, remaining))
                except subprocess.TimeoutExpired:
                    pass
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

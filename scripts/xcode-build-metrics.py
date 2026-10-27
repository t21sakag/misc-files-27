#!/usr/bin/env python3
"""Run xcodebuild verbatim and retain actual elapsed time/Swift compilation work."""
import json
from pathlib import Path
import re
import subprocess
import sys
import time

output = Path(sys.argv[1]).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
started = time.monotonic()
sources = set()
jobs = 0
with output.with_suffix('.log').open('w') as log:
    child = subprocess.Popen(sys.argv[2:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in child.stdout:
        print(line, end='', flush=True)
        log.write(line)
        if line.startswith('SwiftCompile '):
            jobs += 1
            sources.update(re.findall(r'(/[^\n]*?\.swift)(?= |$)', line))
    result = child.wait()
metrics = {'elapsed_seconds': round(time.monotonic() - started, 3), 'swift_compile_jobs': jobs,
           'swift_sources': sorted(sources), 'exit_code': result}
output.write_text(json.dumps(metrics, indent=2) + '\n')
print('Build metrics: ' + json.dumps(metrics), flush=True)
raise SystemExit(result)

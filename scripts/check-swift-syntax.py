#!/usr/bin/env python3
"""Parse app/UI/host Swift sources without requiring Apple SDKs.
This is a syntax gate, not type checking, linking, app building or execution.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--swiftc', default=os.environ.get('SWIFTC') or shutil.which('swiftc'))
parser.add_argument('--report', default='build/swift-syntax-report.json')
args = parser.parse_args()
if not args.swiftc:
    parser.error('Provide --swiftc or SWIFTC pointing to a Swift compiler')
files = sorted({path for root in ['ios/AnkiPad', 'ios/AnkiPadUITests', 'tests'] for path in Path(root).rglob('*.swift')})
if not files:
    raise SystemExit('No Swift sources found; run from the repository root')
version = subprocess.run([args.swiftc, '--version'], capture_output=True, text=True, check=True).stdout.strip()
def parse(path):
    result = subprocess.run([args.swiftc, '-frontend', '-parse', '-swift-version', '5', '-D', 'ANKIPAD_PARSE_UI', str(path)], capture_output=True, text=True)
    return {'file': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'exitCode': result.returncode,
            'diagnostics': result.stdout + result.stderr}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
    results = list(executor.map(parse, files))
report = {'scope': 'syntax only; no Apple SDK type checking or app execution', 'compiler': version,
          'passed': all(result['exitCode'] == 0 for result in results), 'files': results}
path = Path(args.report)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
for result in results:
    if result['diagnostics']:
        print(result['file'] + ':\n' + result['diagnostics'], file=sys.stderr)
print(f"Swift syntax: {len(files)} files, {'PASS' if report['passed'] else 'FAIL'}; report {path}")
raise SystemExit(0 if report['passed'] else 1)

#!/usr/bin/env python3
"""Print structured XCTest failures without requiring the full xcresult download."""
import json
import argparse
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('summary', type=Path)
parser.add_argument('--reject-runtime-warnings', action='store_true')
args = parser.parse_args()
summary = json.loads(args.summary.read_text())
keys = ('result', 'totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'testFailures', 'runtimeWarnings', 'startTime', 'finishTime')
print(json.dumps({key: summary[key] for key in keys if key in summary}, ensure_ascii=False, indent=2))
if args.reject_runtime_warnings and summary.get('runtimeWarnings'):
    raise SystemExit('Runtime warnings require investigation before this milestone can pass')

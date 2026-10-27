#!/usr/bin/env python3
"""Print structured XCTest failures without requiring the full xcresult download."""
import json
from pathlib import Path
import sys

summary = json.loads(Path(sys.argv[1]).read_text())
keys = ('result', 'totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'testFailures', 'startTime', 'finishTime')
print(json.dumps({key: summary[key] for key in keys if key in summary}, ensure_ascii=False, indent=2))

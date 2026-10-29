#!/usr/bin/env python3
"""Execute transferred test products, then require the exact planned case count."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ap = argparse.ArgumentParser()
ap.add_argument('batch', type=int)
ap.add_argument('simulator')
args = ap.parse_args()
plan = json.loads(Path('build/ui-batches.json').read_text())
cases = plan['batches'][args.batch]
assert cases and len(cases) == len(set(cases))
products = list(Path('build/simulator/Build/Products').glob('*.xctestrun'))
assert len(products) == 1, products
result = subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(products[0]),
    '-destination', 'id='+args.simulator, '-parallel-testing-enabled', 'NO',
    '-resultBundlePath', 'build/UITests.xcresult',
    *['-only-testing:AnkiPadUITests/'+c for c in cases]])
subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', 'build/UITests.xcresult'],
               stdout=Path('build/test-summary.json').open('w'), check=True)
subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', 'build/UITests.xcresult'],
               stdout=Path('build/test-tree.json').open('w'), check=True)
summary = json.loads(Path('build/test-summary.json').read_text())
def identities(nodes):
    for node in nodes:
        if node.get('nodeType') == 'Test Case':
            yield node['nodeIdentifier'].removesuffix('()')
        yield from identities(node.get('children', []))
actual = list(identities(json.loads(Path('build/test-tree.json').read_text())['testNodes']))
assert sorted(actual) == sorted(cases), (actual, cases)
assert result.returncode == 0 and summary['totalTestCount'] == len(cases) and summary['passedTests'] == len(cases), summary
assert summary['failedTests'] == summary['skippedTests'] == 0, summary

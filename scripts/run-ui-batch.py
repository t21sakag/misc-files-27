#!/usr/bin/env python3
"""Execute transferred test products, then require the exact planned case count."""
import argparse
import json
import sys
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
# Verify each consumer's own simulator and bundled data, not just the producer.
selections = Path('build/batch-ui-selections.txt')
selections.write_text(''.join('-only-testing:AnkiPadUITests/'+case+'\n' for case in cases))
prerequisites = [sys.executable, str(Path(__file__).with_name('ui-prerequisites.py')),
                 '--simulator', args.simulator, '--selections', str(selections)]
if any(case.endswith(('/testNotesPreviewUsesRepresentativesUntilMultipleRowsSelected',
                       '/testBrowserSelectionOrderSurvivesDeselectionAndReselection')) for case in cases):
    packages = [path for path in Path('build/simulator/Build/Products').rglob('preview.apkg')
                if path.parent.name == 'ReceivedFixtures']
    assert len(packages) == 1, ('Expected one compiled preview fixture', packages)
    prerequisites += ['--preview-package', str(packages[0])]
subprocess.run(prerequisites, check=True)
result = subprocess.run([sys.executable, str(Path(__file__).with_name('run-ui-with-diagnostics.py')),
    '--simulator', args.simulator, '--',
    'xcodebuild', 'test-without-building', '-xctestrun', str(products[0]),
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
assert summary.get('runtimeWarnings') == [], 'Runtime warnings require investigation before the batch can pass'

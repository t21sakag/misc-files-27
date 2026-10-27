"""Guard test discovery/selection when distributing cases across XCTest runners."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
groups = json.loads((root / 'scripts/ui-case-groups.json').read_text())
actual = {}
for path in (root / 'ios/AnkiPadUITests').glob('*.swift'):
    for method in re.findall(r'^    func (test\w+)\(', path.read_text(), re.M):
        assert method not in actual, f'Duplicate XCTest case: {method}'
        actual[method] = path.stem
expected = {}
for group, methods in groups.items():
    for method in methods:
        assert method not in expected, f'Duplicate manifest case: {method}'
        expected[method] = group
assert expected == actual, (expected.keys() - actual.keys(), actual.keys() - expected.keys())
for suite in ['milestone', 'changed', 'profiles', 'shared', 'backups', 'automatic', 'sync', 'reviewer', 'repair']:
    selected = subprocess.check_output(['python3', str(root / 'scripts/select-ui-tests.py'), suite, 'ui'], text=True).splitlines()
    assert selected, suite
    for item in selected:
        group, method = item.split('/')[-2:]
        assert actual[method] == group, item
print(f'PASS: {len(actual)} original cases occur once; all selected suites address their actual XCTest classes')

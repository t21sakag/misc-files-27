"""Check service selection and the fixture-port contract against real test code."""
from pathlib import Path
import re
import runpy
import subprocess

root = Path(__file__).resolve().parents[1]
module = runpy.run_path(str(root/'scripts/select-sync-fixtures.py'))
ports = module['ports']
def scope(name):
    return subprocess.check_output(['python3',str(root/'scripts/select-ui-tests.py'),name,'ui'],text=True).splitlines()
assert ports(scope('regression-repair')) == [18901]
assert ports(scope('upload-only')) == [18901]
assert ports(scope('automatic')) == [18891,18901]
assert ports(scope('incoming-core')) == []
assert ports(scope('reminder-repair')) == []
assert ports(scope('network')) == [18891]
assert ports([]) == [18891,18901]
try: ports(['-only-testing:AnkiPadUITests/Missing/testNotPresent']); raise AssertionError('Unknown case accepted')
except ValueError: pass
support = (root/'ios/AnkiPadUITests/StudyFlowTestSupport.swift').read_text()
default = int(re.search(r'var syncFixturePort: Int \{ (\d+) \}',support)[1])
for path in (root/'ios/AnkiPadUITests').glob('*Tests.swift'):
    source = path.read_text()
    if 'loginToSyncFixture(' in source:
        override = re.search(r'override var syncFixturePort: Int \{ (\d+) \}',source)
        assert module['PORTS'][path.stem] == (int(override[1]) if override else default),path
print('PASS: selected XCTest classes start their actual sync ports; upload-only, mixed, unrelated, all and unknown-case scopes')

"""Verify actual cases request a web host before booting their UI journey."""
from pathlib import Path
import runpy
import subprocess

root = Path(__file__).resolve().parents[1]
needed = runpy.run_path(str(root/'scripts/select-shared-fixture.py'))['needed']
def scope(suite):
    return subprocess.check_output(['python3',str(root/'scripts/select-ui-tests.py'),suite,'ui'],text=True).splitlines()
for suite in ['share-text','shared','changed','incoming-milestone','web-themes']:
    assert needed(scope(suite)),suite
for suite in ['incoming-core','reminder-repair','incoming-image','upload-only']:
    assert not needed(scope(suite)),suite
assert needed([])
try:
    needed(['-only-testing:AnkiPadUITests/Missing/testUnknown'])
    raise AssertionError('Unknown selection accepted')
except ValueError:
    pass
print('PASS: Safari and shared-download cases require their web fixture, unrelated cases do not; invalid selections fail')

"""Guard test discovery/selection when distributing cases across XCTest runners."""
import json
from pathlib import Path
import re
import subprocess
import tempfile

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
for suite in ['milestone', 'changed', 'profiles', 'shared', 'backups', 'automatic', 'sync', 'reviewer', 'repair', 'collapse', 'reminders', 'p1', 'images', 'controls', 'p1-next', 'voice', 'speech', 'occlusion', 'preview', 'network', 'timebox', 'appearance', 'answer-layout', 'layout-regression', 'card-appearance', 'templates', 'conditional-reminders', 'conditional-only', 'reminder-refresh', 'review-header', 'typing-focus', 'card-links', 'template-audio', 'script-dialogs', 'browser-appearance', 'themes', 'milestone-repair', 'button-timing', 'motion', 'motion-only', 'background', 'background-ui', 'background-storage', 'background-selection', 'theme-panels', 'theme-repair', 'batch-check', 'web-themes', 'web-theme-only', 'languages', 'language-only', 'incoming-core', 'incoming-browser', 'incoming-deferred', 'incoming-text', 'incoming-text-cancel', 'incoming-text-save', 'incoming-files', 'incoming-file-cancel', 'incoming-image', 'incoming-raster', 'notification-baseline', 'recovery-baseline', 'incoming-milestone', 'incoming-repair', 'incoming-final', 'incoming-collection-cancel', 'incoming-audio-video', 'incoming-occlusion', 'incoming-final-repair', 'reminder-repair', 'regression-repair', 'upload-only', 'incoming-fields', 'incoming-commit', 'incoming-apkg', 'incoming-colpkg', 'incoming-tsv', 'incoming-invalid', 'incoming-still-note', 'incoming-commit-repair', 'share-text']:
    selected = subprocess.check_output(['python3', str(root / 'scripts/select-ui-tests.py'), suite, 'ui'], text=True).splitlines()
    assert selected, suite
    for item in selected:
        group, method = item.split('/')[-2:]
        assert actual[method] == group, item
with tempfile.TemporaryDirectory() as directory:
    selected_file = Path(directory) / 'selections.txt'
    for suite, workers in [('profiles', 1), ('backups', 1), ('automatic', 1), ('reviewer', 1), ('all', 1)]:
        result = subprocess.check_output(['python3', str(root / 'scripts/select-ui-tests.py'), suite, 'ui'], text=True)
        selected_file.write_text(result)
        actual_workers = subprocess.check_output(['python3', str(root / 'scripts/select-ui-workers.py'), str(selected_file)], text=True).strip()
        assert actual_workers == str(workers), (suite, actual_workers)
language_scope = subprocess.check_output(['python3', str(root / 'scripts/select-ui-tests.py'), 'engine-languages', 'ui'], text=True).splitlines()
assert language_scope == ['-only-testing:AnkiPadUITests/LibraryFlowTests/testNoteCanBeCreatedAndFoundInBrowser']
print(f'PASS: {len(actual)} original cases occur once; all selected suites address their actual XCTest classes')

"""Exercise exact native selections through the real independent-batch planner."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
workflow = (root / '.github/workflows/ipa.yml').read_text()
mode_choices = re.search(r'^      mode:\n.*?^        options: \[([^\n]+)\]$', workflow, re.M | re.S)[1]
assert {value.strip() for value in mode_choices.split(',')} == {'configuration', 'compile', 'ui', 'ipa', 'full'}
expected = {
    'native-widget': {'WidgetGalleryFlowTests/testHomeGalleryAddsSummaryWithActualSharedCountsAndOpensApp'},
    'native-notification': {'NotificationAuthorizationFlowTests/testActualNotificationAuthorizationAndScheduleReplacement'},
}
expected['native-consumers'] = expected['native-widget'] | expected['native-notification']
expected['native-sync'] = {'StudyFlowTests/testFullSyncWithLocalDataRequiresTypedUploadConfirmation'}
expected['native-failures'] = expected['native-notification'] | expected['native-sync']
expected['native-widgets'] = {'WidgetGalleryFlowTests/testSummaryConfigurationSelectsFixedProfileAndKeepsLiveCount', 'WidgetGalleryFlowTests/testDeckListWidgetSelectsDeckAndOpensItsReview', 'WidgetGalleryFlowTests/testAddNoteWidgetOpensEmptyDraftAndCancelKeepsDueCount', 'WidgetGalleryFlowTests/testAnalysisWidgetShowsStoredDeckCountsAndOpensReview', 'WidgetGalleryFlowTests/testFixedSummarySurvivesActiveProfileSwitchAndOpensItsOwnProfile'}


def condition(expression, mode, suite):
    values = {'env.CI_MODE': mode, 'env.UI_SUITE': suite, 'inputs.mode': mode, 'inputs.ui_suite': suite}
    expression = re.sub(r'(?:env|inputs)\.[A-Za-z_]+', lambda match: repr(values[match[0]]), expression)
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    expression = re.sub(r'!(?!=)', ' not ', expression)
    return bool(eval(expression, {'__builtins__': {}}, {'startsWith': lambda value, prefix: value.startswith(prefix)}))


def step_condition(name):
    body = workflow.split('      - name: ' + name + '\n', 1)[1].split('      - ', 1)[0]
    return re.search(r'^        if: (.*)$', body, re.M)[1]


consumer = re.search(r'^  ui-batch:\n.*?^    if: ([^\n]+)$', workflow, re.M | re.S)[1]
assert 'max-parallel: 5' in workflow
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    for suite, cases in expected.items():
        selections = subprocess.check_output([sys.executable, str(root / 'scripts/select-ui-tests.py'), suite, 'ui'], text=True)
        path = base / 'selections.txt'; path.write_text(selections)
        output = base / 'plan.json'
        subprocess.run([sys.executable, str(root / 'scripts/plan-ui-batches.py'), '--selections', str(path), '--output', str(output)],
                       check=True, stdout=subprocess.DEVNULL)
        plan = json.loads(output.read_text())
        assert {case for batch in plan['batches'] for case in batch} == cases
        assert len(plan['batches']) == len(cases) and all(len(batch) == 1 for batch in plan['batches'])
        assert condition(step_condition('Plan independent UI batches'), 'ui', suite)
        assert condition(step_condition('Package compiled test products'), 'ui', suite)
        assert condition(consumer, 'ui', suite)
        assert not condition(step_condition('Execute selected UI cases without rebuilding'), 'ui', suite)
        assert not condition(step_condition('Check simulator and external UI prerequisites'), 'ui', suite)
    for suite in ['all', 'native-consumers', 'widget-gallery']:
        assert condition(step_condition('Plan independent UI batches'), 'full', suite)
        assert condition(consumer, 'full', suite)
    assert condition(step_condition('Execute selected UI cases without rebuilding'), 'ui', 'widget-gallery')
    assert not condition(consumer, 'ui', 'widget-gallery')
    for text in ['', '-only-testing:AnkiPadUITests/UnknownTests/testMissing\n', 'all\n']:
        path.write_text(text)
        rejected = subprocess.run([sys.executable, str(root / 'scripts/plan-ui-batches.py'), '--selections', str(path), '--output', str(output)],
                                  capture_output=True, text=True)
        assert rejected.returncode != 0
print('PASS: exact single/pair native scopes use independent consumers, preserve full routing and reject invalid selections')

"""Exercise failure streaks and stale-review rejection before any Apple CI."""
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('review', root/'scripts/ui-failure-review.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


def run(number, result='failure', mode='ui', attempt=1, steps=None):
    return {'id': number, 'run_attempt': attempt, 'updated_at': f'2026-10-30T10:{number:02}:00Z',
            'status': 'completed', 'conclusion': result, 'display_title': 'Misc checks · '+mode,
            'jobs': [{'steps': steps or []}]}


with tempfile.TemporaryDirectory() as directory:
    workspace = Path(directory)
    (workspace/'tests').mkdir()
    shutil.copy2(root/review.RULES, workspace/review.RULES)
    common = 'ios/AnkiPadUITests/StudyFlowTestSupport.swift'
    (workspace/common).parent.mkdir(parents=True)
    (workspace/common).write_text('shared control implementation\n')
    empty = {'version': 1, 'reviews': []}
    failures = [run(2), run(1)]
    assert review.decision([run(1)], empty, workspace)['decision'] == 'allow'
    assert review.decision(failures, empty, workspace)['decision'] == 'review_required'
    assert review.decision([run(3, 'success'), *failures], empty, workspace)['decision'] == 'allow'
    assert review.decision([run(3, 'success', 'compile'), *failures], empty, workspace)['decision'] == 'review_required'
    assert review.decision([run(3, 'cancelled'), *failures], empty, workspace)['decision'] == 'review_required'
    gate_only = run(3, steps=[{'name': review.GATE, 'conclusion': 'failure'}])
    assert review.decision([gate_only, *failures], empty, workspace)['failed_attempts'] == [[2,1],[1,1]]
    rerun = run(1, attempt=2); rerun['updated_at'] = '2026-10-30T11:00:00Z'
    assert review.decision([rerun, failures[1]], empty, workspace)['failed_attempts'] == [[1,2],[1,1]]
    assert review.decision([run(1), run(1)], empty, workspace)['decision'] == 'allow'
    named = run(3); named['display_title'] = 'Check ui'
    assert review.is_ui_attempt(named)
    named['display_title'] = 'Check compile'
    assert not review.is_ui_attempt(named)
    legacy = run(4); legacy['display_title'] = 'Misc checks'
    legacy['jobs'][0]['steps'] = [{'name': 'Execute selected UI cases without rebuilding', 'conclusion': 'failure'}]
    assert review.decision([legacy, run(2)], empty, workspace)['decision'] == 'review_required'
    for name in ['Plan serial UI batches', 'Plan independent UI batches']:
        fallback = run(4); fallback['display_title'] = 'Misc checks'
        fallback['jobs'][0]['steps'] = [{'name': name, 'conclusion': 'success'}]
        assert review.is_ui_attempt(fallback), name
    draft = {
        'id': 'local-regression', 'covers': [[2,1],[1,1]],
        'classifications': [{'attempt': [number,1], 'kind': 'harness', 'finding': 'Observed selector failure.'} for number in [2,1]],
        'rule_review': {key: 'Observed evidence and common handling reviewed.' for key in json.loads((workspace/review.RULES).read_text())['rules']},
        'root_cause': 'Reproduced harness failure.', 'common_resolution': 'Shared handling reviewed.', 'next_scope': ['one failed case'],
        'evidence': [{'reference': 'https://example.invalid/immutable-evidence', 'sha256': 'a'*64}],
        'reviewed_files': [review.RULES, common],
        'local_checks': [{'name': 'actual command execution', 'argv': [sys.executable, '-c', 'print("verified")']}]
    }
    recorded = review.record_review(draft, failures, workspace)
    approved = {'version': 1, 'reviews': [recorded]}
    assert review.decision(failures, approved, workspace)['review_id'] == draft['id']
    assert review.decision(failures, approved, workspace, ['one failed case'])['decision'] == 'allow'
    assert review.decision(failures, approved, workspace, ['another case'])['decision'] == 'review_required'
    assert review.decision([run(3), *failures], approved, workspace)['decision'] == 'review_required', 'New failure pair needs a new review'
    (workspace/common).write_text('changed after review\n')
    assert review.decision(failures, approved, workspace)['decision'] == 'review_required'
    bad_check = copy.deepcopy(draft)
    bad_check['local_checks'] = [{'name': 'failure', 'argv': [sys.executable, '-c', 'raise SystemExit(1)']}]
    try:
        review.record_review(bad_check, failures, workspace)
    except ValueError:
        pass
    else:
        raise AssertionError('Failed local verification produced a review')
    (workspace/'scripts').mkdir()
    (workspace/'scripts/ui-case-groups.json').write_text(json.dumps({'ExampleTests':['testOne','testTwo']}))
    selections = workspace/'selections.txt'
    selections.write_text('-only-testing:AnkiPadUITests/ExampleTests/testOne\n')
    assert review.selected_cases(selections, workspace) == ['ExampleTests/testOne']
    selections.write_text('')
    assert review.selected_cases(selections, workspace) == ['ExampleTests/testOne','ExampleTests/testTwo']

print('PASS: two UI failures block; success resets; compile/cancel/gate-only do not bypass; reruns count; exact-pair/current-code/executed-check review required')

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
            'run_started_at': f'2026-10-30T10:{number:02}:00Z',
            'status': 'completed', 'conclusion': result, 'display_title': 'Misc checks · '+mode,
            'jobs': [{'started_at': f'2026-10-30T10:{number:02}:00Z', 'steps': [{'name': 'Set up job', 'conclusion': 'success', 'started_at': f'2026-10-30T10:{number:02}:00Z'}] + (steps or [])}]}


original_api = review.github_json
try:
    early = run(10)
    reset = run(20, 'success')
    late = run(10, attempt=2)
    late['jobs'][0]['steps'][0]['started_at'] = '2026-10-30T11:00:00Z'
    newest = run(30)
    latest = [newest, late, reset]
    calls = []
    def api(path):
        calls.append(path)
        if '/workflows/' in path:
            return {'workflow_runs': copy.deepcopy(latest)}
        import re
        match = re.search(r'/runs/(\d+)/attempts/(\d+)(/jobs\?per_page=100)?$', path)
        assert match, path
        key = (int(match[1]), int(match[2]))
        record = {(10, 1): early, (10, 2): late, (20, 1): reset, (30, 1): newest}[key]
        return {'jobs': copy.deepcopy(record['jobs'])} if match[3] else copy.deepcopy(record)
    review.github_json = api
    collected = review.online_history('fixture/repo', 'main', 0, 1)
    assert {review.identity(r) for r in collected} == {(10, 1), (10, 2), (20, 1), (30, 1)}
    assert [review.identity(r) for r in review.recent_failures(collected)] == [(10, 2), (30, 1)]
    assert len(calls) == len(set(calls)), 'Do not refetch an attempt or poll history'
    latest = [late, reset]
    assert [review.identity(r) for r in review.recent_failures(review.online_history('fixture/repo', 'main', 0, 1))] == [(10, 2)]
finally:
    review.github_json = original_api


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
    rerun = run(1, attempt=2); rerun['jobs'][0]['steps'][0]['started_at'] = '2026-10-30T11:00:00Z'
    assert review.decision([rerun, failures[1]], empty, workspace)['failed_attempts'] == [[1,2],[1,1]]
    assert review.decision([run(1), run(1)], empty, workspace)['decision'] == 'allow'
    # A delayed update of an old failed run must not move it after a later
    # successful validation. The next actual failure is only the first one.
    delayed = run(1); delayed['updated_at'] = '2026-11-01T12:00:00Z'
    assert review.recent_failures([delayed, run(2, 'success'), run(3)]) == [run(3)]
    assert review.decision([delayed, run(2, 'success'), run(3)], empty, workspace)['decision'] == 'allow'
    delayed['run_started_at'] = '2026-11-01T13:00:00Z'
    delayed['created_at'] = '2026-11-01T13:00:00Z'
    delayed['jobs'][0]['started_at'] = '2026-11-01T13:00:00Z'
    assert review.decision([delayed, run(2, 'success'), run(3)], empty, workspace)['decision'] == 'allow'
    assert review.decision([delayed, run(2, 'success'), run(3), run(4)], empty, workspace)['failed_attempts'] == [[4,1],[3,1]]
    # Stable start ordering must also retain a late rerun of an older run ID.
    assert review.recent_failures([run(2, 'success'), rerun, run(1)]) == [rerun]
    missing = run(1, attempt=2); del missing['jobs'][0]['steps'][0]['started_at']
    try:
        review.recent_failures([missing])
    except ValueError:
        pass
    else:
        raise AssertionError('Missing executed step start must not fall back to run/job metadata clocks')
    named = run(3); named['display_title'] = 'Check ui'
    assert review.is_ui_attempt(named)
    named['display_title'] = 'Check compile'
    assert not review.is_ui_attempt(named)
    legacy = run(4); legacy['display_title'] = 'Misc checks'
    legacy['jobs'][0]['steps'] += [{'name': 'Execute selected UI cases without rebuilding', 'conclusion': 'failure'}]
    assert review.decision([legacy, run(2)], empty, workspace)['decision'] == 'review_required'
    for name in ['Plan serial UI batches', 'Plan independent UI batches']:
        fallback = run(4); fallback['display_title'] = 'Misc checks'
        fallback['jobs'][0]['steps'] += [{'name': name, 'conclusion': 'success'}]
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

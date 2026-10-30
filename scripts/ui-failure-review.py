#!/usr/bin/env python3
"""Require a concrete common-rule review after two consecutive failed UI runs.

The CI check reads completed run history once, before expensive setup. It is not
a CI monitor. Compile/configuration/IPA checks and review-gate-only failures do
not reset or advance the UI streak. A rerun is a distinct attempt.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
GATE = 'Review repeated validation failures'
RULES = 'tests/ui-test-rules.json'
REVIEWS = 'tests/ui-test-reviews.json'
FAILURES = {'failure', 'timed_out', 'startup_failure', 'action_required'}


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(run):
    return (int(run['id']), int(run.get('run_attempt', 1)))


def run_mode(run):
    title = run.get('display_title', '')
    match = re.fullmatch(r'Check (configuration|compile|ui|ipa|full)', title)
    if match:
        return match.group(1)
    fields = title.split(' · ')
    return fields[1] if len(fields) >= 2 else None


def is_ui_attempt(run):
    steps = [step for job in run.get('jobs', []) for step in job.get('steps', [])]
    if any(step['name'] == GATE and step.get('conclusion') == 'failure' for step in steps):
        return False
    if mode := run_mode(run):
        return mode in ('ui', 'full')
    return any(step['name'] in (
        'Start requested iPadOS 27 simulator before native setup',
        'Execute selected UI cases without rebuilding',
        'Plan serial UI batches') and step.get('conclusion') in ('success', 'failure') for step in steps)


def recent_failures(runs):
    failures = []
    seen = set()
    for run in sorted(runs, key=lambda value: value['updated_at'], reverse=True):
        key = identity(run)
        if key in seen or run.get('status', 'completed') != 'completed':
            continue
        seen.add(key)
        if not is_ui_attempt(run) or run.get('conclusion') in ('cancelled', 'skipped', 'neutral'):
            continue
        if run.get('conclusion') == 'success':
            break
        if run.get('conclusion') in FAILURES:
            failures.append(run)
        if len(failures) == 2:
            break
    return failures


def tracked_file(root, relative):
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Review paths must be relative to the repository')
    resolved = (root/path).resolve()
    if not resolved.is_relative_to(root.resolve()) or not resolved.is_file() or (root/path).is_symlink():
        raise ValueError('Invalid reviewed file: ' + relative)
    return resolved


def validate_review(review, failures, root):
    rules = json.loads((root/RULES).read_text())
    if rules.get('version') != 1:
        raise ValueError('Unsupported rule schema')
    if {tuple(value) for value in review.get('covers', [])} != {identity(run) for run in failures} or len(review.get('covers', [])) != 2:
        raise ValueError('Review must cover the exact two failed run attempts')
    classifications = review.get('classifications', [])
    if {tuple(item.get('attempt', [])) for item in classifications} != {identity(run) for run in failures}:
        raise ValueError('Classify both failed attempts')
    if any(item.get('kind') not in {'application', 'harness', 'environment', 'inspection', 'undetermined'} or not item.get('finding') for item in classifications):
        raise ValueError('Every failure needs its category and evidence-based finding')
    assessments = review.get('rule_review', {})
    if set(assessments) != set(rules['rules']):
        raise ValueError('Review every common rule, including rules that need no change')
    if any(not isinstance(value, str) or not value.strip() for value in assessments.values()):
        raise ValueError('Every rule needs a concrete assessment')
    for name in ['root_cause', 'common_resolution', 'next_scope']:
        if not review.get(name):
            raise ValueError('Missing review field: ' + name)
    files = review.get('files', {})
    if RULES not in files or not set(files).intersection(rules['common_implementations']):
        raise ValueError('Review must include the shared rules and their implementation')
    for name, expected in files.items():
        if checksum(tracked_file(root, name)) != expected:
            raise ValueError('Reviewed code changed after local checks: ' + name)
    evidence = review.get('evidence', [])
    if not evidence or any(not item.get('reference') or not re.fullmatch('[a-f0-9]{64}', item.get('sha256', '')) for item in evidence):
        raise ValueError('Review needs references and content hashes for observed evidence')
    checks = review.get('checks', [])
    if not checks or any(check.get('exit_code') != 0 or not check.get('argv') or not re.fullmatch('[a-f0-9]{64}', check.get('stdout_sha256', '')) for check in checks):
        raise ValueError('Local verification must have completed successfully')


def decision(runs, reviews, root, selected_cases=None):
    if reviews.get('version') != 1:
        raise ValueError('Unsupported review schema')
    failures = recent_failures(runs)
    report = {'threshold': 2, 'failed_attempts': [list(identity(run)) for run in failures], 'decision': 'allow'}
    if len(failures) < 2:
        return report
    errors = []
    for review in reversed(reviews.get('reviews', [])):
        try:
            validate_review(review, failures, root)
            if selected_cases is not None and (not selected_cases or not set(selected_cases).issubset(review['next_scope'])):
                raise ValueError('Selected cases exceed the reviewed next scope')
            return dict(report, review_id=review['id'])
        except (ValueError, KeyError) as error:
            errors.append(str(error))
    return dict(report, decision='review_required', reason='Two consecutive failed UI attempts require a common-rule review', review_errors=errors[-3:])


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        return None  # Do not forward the CI token to another origin.


def github_json(path):
    headers = {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
    if token := os.environ.get('GITHUB_TOKEN'):
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request('https://api.github.com/' + path, headers=headers)
    with urllib.request.build_opener(NoRedirect).open(request, timeout=20) as response:
        data = response.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        raise ValueError('History response exceeded its bound')
    return json.loads(data)


def online_history(repo, branch, current_run, current_attempt):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid repository')
    from urllib.parse import urlencode
    query = urlencode({'branch': branch, 'status': 'completed', 'per_page': 30})
    runs = github_json(f'repos/{repo}/actions/workflows/ipa.yml/runs?{query}')['workflow_runs']
    runs = [run for run in runs if int(run['id']) != current_run]
    for attempt in range(current_attempt-1, max(0, current_attempt-3), -1):
        runs.append(github_json(f'repos/{repo}/actions/runs/{current_run}/attempts/{attempt}'))
    selected = []
    for run in sorted(runs, key=lambda value: value['updated_at'], reverse=True):
        mode = run_mode(run)
        if mode is not None and mode not in ('ui', 'full'):
            continue
        attempt = int(run.get('run_attempt', 1))
        run['jobs'] = github_json(f'repos/{repo}/actions/runs/{run["id"]}/attempts/{attempt}/jobs?per_page=100')['jobs']
        selected.append(run)
        if len(recent_failures(selected)) == 2:
            break
        if run['conclusion'] == 'success' and is_ui_attempt(run):
            break
    return selected


def selected_cases(path, root):
    groups = json.loads((root/'scripts/ui-case-groups.json').read_text())
    known = {name+'/'+method for name, methods in groups.items() for method in methods}
    arguments = path.read_text().splitlines()
    if not arguments:
        return sorted(known)
    prefix = '-only-testing:AnkiPadUITests/'
    cases = []
    for value in arguments:
        if not value.startswith(prefix) or value[len(prefix):] not in known:
            raise ValueError('Unknown UI selection')
        cases.append(value[len(prefix):])
    return cases


def record_review(draft, runs, root):
    review = {key: value for key, value in draft.items() if key not in ('local_checks', 'reviewed_files')}
    review['files'] = {name: checksum(tracked_file(root, name)) for name in draft['reviewed_files']}
    review['checks'] = []
    for check in draft['local_checks']:
        argv = [os.environ.get(value[4:], '') if value.startswith('env:') else value for value in check['argv']]
        if not all(argv):
            raise ValueError('Missing executable environment variable')
        timeout = int(check.get('timeout_seconds', 120))
        if not 1 <= timeout <= 600:
            raise ValueError('Invalid local verification timeout')
        try:
            result = subprocess.run(argv, cwd=root, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise ValueError('Local check timed out: ' + check['name']) from None
        if result.returncode:
            raise ValueError('Local check failed: ' + check['name'] + '\n' + result.stdout[-2000:] + result.stderr[-2000:])
        review['checks'].append({'name': check['name'], 'argv': check['argv'], 'exit_code': 0,
            'stdout_sha256': hashlib.sha256(result.stdout.encode()).hexdigest()})
    review['checked_at'] = datetime.now(timezone.utc).isoformat()
    validate_review(review, recent_failures(runs), root)
    return review


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['check', 'record'])
    parser.add_argument('--history', type=Path)
    parser.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY', ''))
    parser.add_argument('--branch', default=os.environ.get('GITHUB_REF_NAME', 'main'))
    parser.add_argument('--current-run', type=int, default=int(os.environ.get('GITHUB_RUN_ID', '0')))
    parser.add_argument('--current-attempt', type=int, default=int(os.environ.get('GITHUB_RUN_ATTEMPT', '1')))
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--draft', type=Path)
    parser.add_argument('--selections', type=Path)
    parser.add_argument('--output', type=Path, default=Path('build/ui-review-gate.json'))
    args = parser.parse_args()
    root = args.root.resolve()
    report = {'decision': 'unavailable'}
    try:
        runs = json.loads(args.history.read_text()) if args.history else online_history(args.repo, args.branch, args.current_run, args.current_attempt)
        reviews = json.loads((root/REVIEWS).read_text())
        if args.mode == 'record':
            if args.draft is None:
                raise ValueError('A review draft is required')
            reviews['reviews'].append(record_review(json.loads(args.draft.read_text()), runs, root))
            (root/REVIEWS).write_text(json.dumps(reviews, ensure_ascii=False, indent=2)+'\n')
        scope = selected_cases(args.selections, root) if args.selections else None
        report = decision(runs, reviews, root, scope)
    except (OSError, ValueError, KeyError) as error:
        report['reason'] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report['decision'] == 'allow' else 2


if __name__ == '__main__':
    raise SystemExit(main())

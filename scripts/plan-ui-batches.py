#!/usr/bin/env python3
"""Partition every discovered case once; estimates affect placement, not scope."""
import argparse
import json
import math
from pathlib import Path

def plan(groups, durations, proof=False, selected=None):
    cases = [name + '/' + method for name, methods in groups.items() for method in methods]
    if not cases or len(cases) != len(set(cases)):
        raise ValueError('Expected nonempty, unique actual cases')
    if selected is not None:
        if proof or not selected or len(selected) != len(set(selected)) or not set(selected).issubset(cases):
            raise ValueError('Selected batches need a nonempty, unique subset of actual cases')
        cases = list(selected)
    if proof:
        cases = ['StudyFlowTests/testAnkiWebLoginAndTokenSurviveRelaunch',
                 'MediaFlowTests/testZImageOcclusionCanBeCreatedFromPhoto']
        if not set(cases).issubset({c + '/' + m for c, ms in groups.items() for m in ms}):
            raise ValueError('Missing proof case')
    batches = [[] for _ in range(2 if proof else min(5, len(cases)))]
    totals = [0.0] * len(batches)
    for case in sorted(cases, key=lambda c: (-durations.get(c, 180), c)):
        index = min(range(len(batches)), key=lambda i: (totals[i], i))
        batches[index].append(case)
        totals[index] += durations.get(case, 180)
    assert sorted(c for batch in batches for c in batch) == sorted(cases)
    return {'batches': batches, 'estimated_seconds': totals}

def validate_timeout(result, timeout_minutes):
    # Allow for simulator/setup/export plus variation in the observed cases.
    # Do not launch a batch whose own estimate already exhausts its runner.
    required = math.ceil((max(result['estimated_seconds']) * 1.25 + 600) / 60)
    if timeout_minutes < required:
        raise ValueError(f'Batch requires at least {required} minutes including setup and 25% timing margin; runner allows {timeout_minutes}')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--proof', action='store_true')
    ap.add_argument('--selections', type=Path)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--timeout-minutes', type=int)
    args = ap.parse_args()
    here = Path(__file__).parent
    selected = None
    if args.selections is not None:
        prefix = '-only-testing:AnkiPadUITests/'
        lines = args.selections.read_text().splitlines()
        if any(not line.startswith(prefix) for line in lines):
            raise ValueError('Expected exact XCTest selections')
        selected = [line[len(prefix):] for line in lines]
    result = plan(json.loads((here/'ui-case-groups.json').read_text()), json.loads((here/'ui-case-durations.json').read_text()), args.proof, selected)
    if args.timeout_minutes is not None:
        validate_timeout(result, args.timeout_minutes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print('matrix=' + json.dumps(list(range(len(result['batches'])))))

#!/usr/bin/env python3
"""Partition every discovered case once; estimates affect placement, not scope."""
import argparse
import json
from pathlib import Path

def plan(groups, durations, proof=False):
    cases = [name + '/' + method for name, methods in groups.items() for method in methods]
    if len(cases) != len(set(cases)):
        raise ValueError('Duplicate cases')
    if proof:
        cases = ['StudyFlowTests/testAnkiWebLoginAndTokenSurviveRelaunch',
                 'MediaFlowTests/testZImageOcclusionCanBeCreatedFromPhoto']
        if not set(cases).issubset({c + '/' + m for c, ms in groups.items() for m in ms}):
            raise ValueError('Missing proof case')
    batches = [[] for _ in range(2 if proof else 3)]
    totals = [0.0] * len(batches)
    for case in sorted(cases, key=lambda c: (-durations.get(c, 180), c)):
        index = min(range(len(batches)), key=lambda i: (totals[i], i))
        batches[index].append(case)
        totals[index] += durations.get(case, 180)
    assert sorted(c for batch in batches for c in batch) == sorted(cases)
    return {'batches': batches, 'estimated_seconds': totals}

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--proof', action='store_true')
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    here = Path(__file__).parent
    result = plan(json.loads((here/'ui-case-groups.json').read_text()), json.loads((here/'ui-case-durations.json').read_text()), args.proof)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print('matrix=' + json.dumps(list(range(len(result['batches'])))))

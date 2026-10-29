#!/usr/bin/env python3
"""Select native sync services from actual XCTest classes, not suite nicknames."""
import json
from pathlib import Path
import sys

PORTS = {'StudyFlowTests': 18891, 'SyncSettingsFlowTests': 18891, 'AutomaticSyncTests': 18901}
def ports(arguments):
    groups = json.loads(Path(__file__).with_name('ui-case-groups.json').read_text())
    cases = {name + '/' + method for name, methods in groups.items() for method in methods}
    if not arguments:
        return sorted(set(PORTS.values()))
    selected = set()
    for argument in arguments:
        prefix = '-only-testing:AnkiPadUITests/'
        if not argument.startswith(prefix) or argument[len(prefix):] not in cases:
            raise ValueError('Invalid fixture selection: ' + argument)
        name = argument[len(prefix):].split('/')[0]
        if name in PORTS: selected.add(PORTS[name])
    return sorted(selected)

if __name__ == '__main__':
    for port in ports(Path(sys.argv[1]).read_text().splitlines()):
        print(port)

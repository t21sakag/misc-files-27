#!/usr/bin/env python3
"""Select the synthetic web host from actual cases, using standard Python only."""
import json
from pathlib import Path
import sys

def needed(arguments):
    groups = json.loads(Path(__file__).with_name('ui-case-groups.json').read_text())
    cases = {name+'/'+method for name, methods in groups.items() for method in methods}
    if not arguments:
        return True
    required = False
    for argument in arguments:
        prefix = '-only-testing:AnkiPadUITests/'
        if not argument.startswith(prefix) or argument[len(prefix):] not in cases:
            raise ValueError('Invalid fixture selection: '+argument)
        name, method = argument[len(prefix):].split('/')
        required |= name == 'ShareExtensionFlowTests' or method == 'testZZSharedDeckCanBeDownloadedAndImported'
    return required

if __name__ == '__main__':
    print('yes' if needed(Path(sys.argv[1]).read_text().splitlines()) else 'no')

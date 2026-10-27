#!/usr/bin/env python3
"""Do not boot unused clone runners when a selected suite has only one class."""
import json
from pathlib import Path
import sys

selections = Path(sys.argv[1]).read_text().splitlines()
if selections:
    classes = set()
    for item in selections:
        prefix, target, test_class, method = item.replace(':', '/', 1).split('/')
        assert prefix == '-only-testing' and target == 'AnkiPadUITests'
        assert test_class.isidentifier() and method.isidentifier()
        classes.add(test_class)
else:
    classes = set(json.loads(Path(__file__).with_name('ui-case-groups.json').read_text()))
# Establish a reliable serial baseline: full-run failures include blank WebKit
# pages and accessibility snapshot timeouts that did not reproduce in focused
# runs. Keep the case partition/independent fixtures for later comparison.
print(1)

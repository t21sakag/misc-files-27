"""Keep workflow-dispatch choices aligned with every supported UI selection."""
import ast
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
tree = ast.parse((root/'scripts/select-ui-tests.py').read_text())
suites = next(ast.literal_eval(node.value) for node in tree.body
              if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'suites' for target in node.targets))
workflow = (root/'.github/workflows/ipa.yml').read_text()
block = re.search(r'^      ui_suite:\n(?P<body>(?:^        .*\n)+)', workflow, re.M)
assert block, 'Missing ui_suite workflow input'
match = re.search(r'^        options: \[(.*?)\]$', block['body'], re.M)
assert match, 'Expected explicit dispatch choices'
choices = [value.strip() for value in match[1].split(',')]
assert len(choices) == len(set(choices)), 'Duplicate dispatch choice'
expected = set(suites) | {'all'}  # all deliberately emits no -only-testing flags.
assert set(choices) == expected, {'missing': sorted(expected-set(choices)), 'undefined': sorted(set(choices)-expected)}
print(f'PASS: {len(choices)} dispatch choices match the complete UI selector catalog')

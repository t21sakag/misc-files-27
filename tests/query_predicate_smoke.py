import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('query_lint', root/'scripts/check-ui-query-predicates.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for method in ['matching', 'containing']:
    for key in ['hittable', 'isHittable']:
        source = '\nquery.'+method+'(\n NSPredicate(format: "'+key+' == true"))'
        assert module.violations(source) == [2]
for source in [
    'query.matching(NSPredicate(format: "label == %@", title))',
    'query.matching(NSPredicate(format: "label == \'hittable\'"))',
    'XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)',
    'let ready = element.isHittable',
    'query.matching(NSPredicate(format: "label == \\"hittable\\""))',
]:
    assert module.violations(source) == [], source
print('PASS: unsupported query keys rejected; object readiness and literal labels accepted')

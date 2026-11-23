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

for source in ['let fields = app.searchFields', 'app.searchFields.firstMatch', 'app.searchFields.element', 'app.searchFields.count', 'app.searchFields\n .allElementsBoundByIndex']:
    assert module.unscoped_search_fields(source) == [1], source
for source in ['app.navigationBars["カードブラウザー"].searchFields', 'app.searchFields["デッキを検索"]', 'app.searchFields.matching(NSPredicate(format: "label == %@", title))']:
    assert module.unscoped_search_fields(source) == [], source
print('PASS: root SearchField ambiguity rejected before CI; scoped or semantically narrowed queries remain allowed')

for source in ['outer.switches.firstMatch.exists', 'app.switches["automatic-sync"].switches.firstMatch', 'drawing.switches\n .firstMatch']:
    assert module.chained_switch_first_match(source) == [1], source
for source in ['query.children(matching: .switch)', 'app.switches.matching(identifier: "remove-app-animations")']:
    assert module.chained_switch_first_match(source) == [], source
print('PASS: chained .switches.firstMatch rejected before CI; bulk children/matching switch queries remain allowed')

for source in ['revealFormControl(query.firstMatch, in: form)', 'revealFormControl(matching: query.firstMatch, in: form)', 'revealFormControl(app.buttons["x"].firstMatch, in: form)']:
    assert module.reveal_form_control_first_match(source) == [1], source
for source in ['revealFormControl(matching: query, in: form)', 'revealFormControl(query, in: form)', 'revealFormControl(controls.element, in: form)']:
    assert module.reveal_form_control_first_match(source) == [], source
print('PASS: revealFormControl with .firstMatch rejected before CI; bulk query and explicit elements remain allowed')

dup_source = '''class SampleTests: XCTestCase {
    func foo(_ x: XCUIElementQuery, in y: XCUIElement) {}
    func foo(_ x: XCUIElement, in y: XCUIElement) {}
}'''
assert module.duplicate_objc_selectors(dup_source) == [(3, 'foo(_:in:)', 2)], module.duplicate_objc_selectors(dup_source)
ok_label = '''class SampleTests: XCTestCase {
    func foo(matching x: XCUIElementQuery, in y: XCUIElement) {}
    func foo(_ x: XCUIElement, in y: XCUIElement) {}
}'''
assert module.duplicate_objc_selectors(ok_label) == [], module.duplicate_objc_selectors(ok_label)
ok_nonobjc = '''class SampleTests: XCTestCase {
    @nonobjc func foo(_ x: XCUIElementQuery, in y: XCUIElement) {}
    func foo(_ x: XCUIElement, in y: XCUIElement) {}
}'''
assert module.duplicate_objc_selectors(ok_nonobjc) == [], module.duplicate_objc_selectors(ok_nonobjc)
ok_separate = '''class FirstTests: XCTestCase {
    func foo(_ x: XCUIElement, in y: XCUIElement) {}
}
class SecondTests: XCTestCase {
    func foo(_ x: XCUIElement, in y: XCUIElement) {}
}'''
assert module.duplicate_objc_selectors(ok_separate) == [], module.duplicate_objc_selectors(ok_separate)
print('PASS: duplicate Objective-C selectors on XCTestCase subclasses rejected before CI')

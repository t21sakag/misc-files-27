#!/usr/bin/env python3
"""Reject known unsupported hit-testing keys in literal XCTest query predicates.

This covers direct matching/containing(NSPredicate(format: ...)) calls only.
Object-based expectations may inspect isHittable; query predicates cannot.
Variable-built predicates and all other API/type checks remain Apple's job.
"""
from pathlib import Path
import re

QUERY = re.compile(r'\.(?:matching|containing)\s*\(\s*NSPredicate\s*\(\s*format:\s*"((?:\\.|[^"\\])*)"')


def violations(source):
    result = []
    for match in QUERY.finditer(source):
        expression = match[1].replace('\\"', '"').replace('\\\\', '\\')
        # A literal button label named "hittable" is not an attribute lookup.
        expression = re.sub(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", ' ', expression)
        if re.search(r'\b(?:isHittable|hittable)\b', expression):
            result.append(source[:match.start()].count('\n') + 1)
    return result


def unscoped_search_fields(source):
    # UIKit retains the deck search field behind a modal browser. A root query
    # (even firstMatch/element) has no foreground or semantic disambiguation.
    pattern = r"\bapp\.searchFields\b(?!\s*(?:\.matching\s*\(|\.containing\s*\(|\[))"
    return [source[:match.start()].count('\n') + 1 for match in re.finditer(pattern, source)]


def chained_switch_first_match(source):
    # Chained .switches.firstMatch forces XCTest into lazy node-by-node AX
    # faulting (XCTFilteringTransformerIterator) across large SwiftUI Forms
    # and bypasses readTestSwitchValue/setTestSwitch bulk snapshot resolution.
    pattern = r"\.switches\s*\.firstMatch\b"
    return [source[:match.start()].count('\n') + 1 for match in re.finditer(pattern, source)]


def reveal_form_control_first_match(source):
    # Passing a first-match element into revealFormControl forces lazy AX
    # traversal on every reveal attempt instead of bulk query resolution.
    pattern = r"\brevealFormControl\s*\([^,\n]*\.firstMatch\b"
    return [source[:match.start()].count('\n') + 1 for match in re.finditer(pattern, source)]


def duplicate_objc_selectors(source):
    # Swiftc -frontend -parse does not detect Objective-C selector collisions
    # between overloaded methods on XCTestCase subclasses.
    lines = source.splitlines()
    seen = {}
    duplicates = []
    type_re = re.compile(
        r"^(?:(?:final|open|public|internal|private|fileprivate|@[\w().: ]+)\s+)*(?:class|struct|enum|extension|protocol)\s+"
    )
    func_re = re.compile(
        r"^    (?:(?:override|open|public|internal|class|static|@objc)\s+)*func\s+([A-Za-z_]\w*)\s*\("
    )
    i = 0
    while i < len(lines):
        line = lines[i]
        if type_re.match(line):
            seen = {}
            i += 1
            continue
        match = func_re.match(line)
        if match:
            prev = lines[i - 1] if i > 0 else ""
            if "@nonobjc" not in prev and "@nonobjc" not in line:
                name = match.group(1)
                j = i
                depth = 0
                params = []
                done = False
                while j < len(lines) and not done:
                    chunk = lines[j][match.end() - 1:] if j == i else lines[j]
                    for ch in chunk:
                        if ch == "(":
                            if depth >= 1:
                                params.append(ch)
                            depth += 1
                        elif ch == ")":
                            depth -= 1
                            if depth == 0:
                                done = True
                                break
                            params.append(ch)
                        elif depth >= 1:
                            params.append(ch)
                    j += 1
                param_str = "".join(params).strip()
                labels = []
                if param_str:
                    parts, cur, nest = [], [], 0
                    for ch in param_str:
                        if ch in "([<":
                            nest += 1
                        elif ch in ")]>":
                            nest -= 1
                        elif ch == "," and nest == 0:
                            parts.append("".join(cur))
                            cur = []
                            continue
                        cur.append(ch)
                    parts.append("".join(cur))
                    for part in parts:
                        head = part.split(":", 1)[0].strip()
                        tokens = head.split()
                        labels.append(tokens[0] if tokens else "")
                key = (name, tuple(labels))
                selector = f"{name}({''.join(label + ':' for label in labels)})"
                if key in seen:
                    duplicates.append((i + 1, selector, seen[key]))
                else:
                    seen[key] = i + 1
        i += 1
    return duplicates


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    files = sorted((root/'ios/AnkiPadUITests').rglob('*.swift'))
    errors = [f'{path.relative_to(root)}:{line}: hit testing belongs in shared readiness, not a query predicate'
              for path in files for line in violations(path.read_text())]
    errors += [f'{path.relative_to(root)}:{line}: root SearchField queries need foreground or semantic narrowing'
               for path in files for line in unscoped_search_fields(path.read_text())]
    errors += [f'{path.relative_to(root)}:{line}: use shared readTestSwitchValue/setTestSwitch instead of chained .switches.firstMatch'
               for path in files for line in chained_switch_first_match(path.read_text())]
    errors += [f'{path.relative_to(root)}:{line}: pass an XCUIElementQuery or non-firstMatch element to revealFormControl instead of .firstMatch'
               for path in files for line in reveal_form_control_first_match(path.read_text())]
    errors += [f'{path.relative_to(root)}:{line}: duplicate Objective-C selector {selector} in XCTestCase subclass (previously declared on line {first_line}); use a distinct argument label or @nonobjc'
               for path in files for line, selector, first_line in duplicate_objc_selectors(path.read_text())]
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {len(files)} UI files reject unsupported hit-testing predicates, unscoped root search fields, chained .switches.firstMatch, revealFormControl .firstMatch and duplicate Objective-C selectors')

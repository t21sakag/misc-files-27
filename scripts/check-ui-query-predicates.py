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


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    files = sorted((root/'ios/AnkiPadUITests').rglob('*.swift'))
    errors = [f'{path.relative_to(root)}:{line}: hit testing belongs in shared readiness, not a query predicate'
              for path in files for line in violations(path.read_text())]
    errors += [f'{path.relative_to(root)}:{line}: root SearchField queries need foreground or semantic narrowing'
               for path in files for line in unscoped_search_fields(path.read_text())]
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {len(files)} UI files reject unsupported hit-testing predicates and unscoped root search fields')

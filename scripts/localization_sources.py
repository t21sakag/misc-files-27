"""Inventory Swift string literals without treating comments or embedded scripts as Swift code."""
import json
from pathlib import Path


def scan(source):
    found = []
    length = len(source)

    def comment(i):
        if source.startswith('//', i):
            end = source.find('\n', i+2)
            return length if end == -1 else end
        if source.startswith('/*', i):
            depth = 1; i += 2
            while i < length and depth:
                if source.startswith('/*', i): depth += 1; i += 2
                elif source.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
            return i
        return i

    def quoted(i):
        start = i
        while i < length and source[i] == '#': i += 1
        hashes = source[start:i]
        if i >= length or source[i] != '"': return None
        delimiter = '"""' if source.startswith('"""', i) else '"'
        i += len(delimiter); body_start = i
        escapes = '\\'+hashes
        expressions = []
        while i < length:
            if source.startswith(delimiter+hashes, i):
                end = i + len(delimiter+hashes)
                found.append({'start':start,'end':end,'text':source[start:end], 'raw':bool(hashes), 'multiline':len(delimiter)==3, 'expressions':expressions})
                return end
            if source.startswith(escapes, i):
                i += len(escapes)
                if i < length and source[i] == '(':
                    expr_start = i+1
                    i = code(i+1, depth=1)
                    expressions.append(source[expr_start:i-1])
                else: i += 1
            else: i += 1
        raise ValueError(f'Unclosed string {start}')

    def code(i, depth=0):
        while i < length:
            next_i = comment(i)
            if next_i != i: i = next_i; continue
            next_i = quoted(i) if source[i] in '#"' else None
            if next_i is not None: i = next_i; continue
            if depth:
                if source[i] == '(': depth += 1
                elif source[i] == ')':
                    depth -= 1
                    if depth == 0: return i+1
            i += 1
        if depth: raise ValueError('Unclosed interpolation')
        return i

    code(0)
    return sorted(found,key=lambda s:s['start'])


def is_japanese(text):
    return any('\u3040' <= ch <= '\u30ff' or '\u3400' <= ch <= '\u9fff' for ch in text)


def localization_key(value):
    text = value['text']
    for expression in value['expressions']:
        string = expression.startswith(('String(', 'profile.name', 'entry.name', 'deck.name', 'date.formatted(', 'removing ??')) or expression == 'field'
        text = text.replace('\\(' + expression + ')', '%@' if string else '%lld', 1)
    return json.loads(text)

#!/usr/bin/env python3
"""Reduce actual settings sections without rewriting state, loading or callbacks.

DEBUG-only source copies distinguish composition from the minimal scenes.
The full copy controls for the copying/entry itself; left/right partition the
other sections and both retain the actual toolbar's entire section.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'ios/AnkiPad/SettingsView.swift'
OUTPUT = 'ios/AnkiPad/ToolbarSettingsReductions.generated.swift'
MANIFEST = 'tests/toolbar-focus-reductions.json'


def generate():
    raw = (ROOT / SOURCE).read_text()
    lines = raw.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith('                    Section')]
    end = [i for i, line in enumerate(lines) if line == '                } else { ProgressView() }\n']
    if len(end) != 1 or not starts or starts[-1] >= end[0]:
        raise ValueError('Settings structure changed; inspect section boundaries before regenerating')
    boundaries = starts[1:] + end
    blocks = [''.join(lines[a:b]) for a, b in zip(starts, boundaries)]
    labels = [re.search(r'AppText\.localized\("([^"]+)"\)', block).group(1) for block in blocks]
    if len(labels) != len(set(labels)) or labels.count('学習操作') != 1:
        raise ValueError('Ambiguous settings sections')
    shared = labels.index('学習操作')
    others = [i for i in range(len(blocks)) if i != shared]
    middle = len(others) // 2
    variants = {
        'full': list(range(len(blocks))),
        'left': sorted([shared] + others[:middle]),
        'right': sorted([shared] + others[middle:]),
    }
    assert set(variants['left']) | set(variants['right']) == set(variants['full'])
    assert set(variants['left']) & set(variants['right']) == {shared}
    digest = hashlib.sha256(raw.encode()).hexdigest()
    prefix = ''.join(lines[:starts[0]])
    suffix = ''.join(lines[end[0]:])
    chunks = ['#if DEBUG\n// Generated from SettingsView.swift; do not edit by hand.\n',
              '// Source SHA256: ' + digest + '\n']
    manifest = {'source': SOURCE, 'source_sha256': digest, 'shared_section': labels[shared], 'variants': {}}
    for name, selected in variants.items():
        typename = 'Toolbar' + name.title() + 'SettingsReductionView'
        body = prefix + ''.join(blocks[i] for i in selected) + suffix
        assert body.count('struct SettingsView: View {') == 1
        body = body.replace('struct SettingsView: View {', 'struct ' + typename + ': ToolbarModelSettingsFocusView {', 1)
        field = '    @ObservedObject var model: StudyModel\n'
        assert body.count(field) == 1
        body = body.replace(field, field + '    init(model: StudyModel) { _model = ObservedObject(wrappedValue: model) }\n', 1)
        chunks += ['\n// Variant: ' + name + '\n', body]
        manifest['variants'][name] = {'type': typename, 'sections': [labels[i] for i in selected]}
    chunks.append('#endif\n')
    output = ''.join(chunks)
    manifest['generated_sha256'] = hashlib.sha256(output.encode()).hexdigest()
    return output, json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source, manifest = generate()
    for relative, expected in [(OUTPUT, source), (MANIFEST, manifest)]:
        path = ROOT / relative
        if args.check:
            if not path.is_file() or path.read_text() != expected:
                raise SystemExit('Regenerate and inspect settings reductions: ' + relative)
        else:
            path.write_text(expected)
    print('PASS: actual-source full control and complete/complementary section reductions; state/loading/callbacks retained')


if __name__ == '__main__':
    main()

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
PLAN = 'tests/toolbar-focus-reduction-plan.json'


def source_parts(raw):
    lines = raw.splitlines(keepends=True)
    begin = [i for i, line in enumerate(lines) if line == '                if loaded {\n']
    end = [i for i, line in enumerate(lines) if line == '                } else { ProgressView() }\n']
    if len(begin) != 1 or len(end) != 1 or begin[0] >= end[0]:
        raise ValueError('Settings structure changed; inspect section boundaries before regenerating')
    if '"""' in ''.join(lines[begin[0]:end[0]]):
        raise ValueError('Inspect multiline-string indentation before reducing settings')
    blocks = []
    index = begin[0] + 1
    while index < end[0]:
        line = lines[index]
        if re.match(r'^ +Section\b', line):
            indent = len(line) - len(line.lstrip())
            if indent < 20:
                raise ValueError('Unexpected section indentation')
            stop = index + 1
            if line.rstrip().endswith('{'):
                while stop < end[0] and lines[stop] != ' ' * indent + '}\n':
                    stop += 1
                if stop >= end[0]:
                    raise ValueError('Missing section end')
                stop += 1
            elif line.count('{') != line.count('}'):
                raise ValueError('Inspect single-line section before reducing settings')
            # Normalize only code indentation. Full-copy control below retains
            # the exact source layout, including feature-preserving Groups.
            blocks.append(''.join(value[indent-20:] if value.strip() else value for value in lines[index:stop]))
            index = stop
            continue
        if line.strip() not in ('', 'Group {', '}') and not line.lstrip().startswith('//'):
            raise ValueError('Unexpected content outside top-level settings sections')
        index += 1
    labels = [re.search(r'AppText\.localized\("([^"]+)"\)', block).group(1) for block in blocks]
    if len(labels) != len(set(labels)) or labels.count('学習操作') != 1:
        raise ValueError('Ambiguous settings sections')
    return ''.join(lines[:begin[0]+1]), blocks, labels, ''.join(lines[end[0]:])


def generate():
    raw = (ROOT / SOURCE).read_text()
    prefix, blocks, labels, suffix = source_parts(raw)
    plan_raw = (ROOT / PLAN).read_text()
    plan = json.loads(plan_raw)
    selected_labels = {key: plan[key] for key in ('shared', 'left', 'right')}
    if any(len(value) != len(set(value)) for value in selected_labels.values()):
        raise ValueError('Duplicate reduction-plan section')
    shared = set(selected_labels['shared'])
    left, right = set(selected_labels['left']), set(selected_labels['right'])
    if '学習操作' not in shared or shared & (left | right) or left & right:
        raise ValueError('Only declared shared sections can overlap')
    if not left or not right or shared | left | right != set(labels):
        raise ValueError('Reduction plan must cover every actual source section')
    variants = {
        'full': list(range(len(blocks))),
        'left': [i for i, label in enumerate(labels) if label in shared | left],
        'right': [i for i, label in enumerate(labels) if label in shared | right],
    }
    assert set(variants['left']) | set(variants['right']) == set(variants['full'])
    assert {labels[i] for i in set(variants['left']) & set(variants['right'])} == shared
    digest = hashlib.sha256(raw.encode()).hexdigest()
    chunks = ['#if DEBUG\n// Generated from SettingsView.swift; do not edit by hand.\n',
              '// Source SHA256: ' + digest + '\n']
    manifest = {'source': SOURCE, 'source_sha256': digest,
                'plan': PLAN, 'plan_sha256': hashlib.sha256(plan_raw.encode()).hexdigest(),
                'stage': plan['stage'], 'shared_sections': selected_labels['shared'],
                'section_sha256': {label: hashlib.sha256(block.encode()).hexdigest() for label, block in zip(labels, blocks)},
                'variants': {}}
    for name, selected in variants.items():
        typename = 'Toolbar' + name.title() + 'SettingsReductionView'
        body = raw if name == 'full' else prefix + ''.join(blocks[i] for i in selected) + suffix
        assert body.count('struct SettingsView: View {') == 1
        body = body.replace('struct SettingsView: View {', 'struct ' + typename + ': ToolbarModelSettingsFocusView {', 1)
        field = '    @ObservedObject var model: StudyModel\n'
        assert body.count(field) == 1
        body = body.replace(field, field + '    init(model: StudyModel) { _model = ObservedObject(wrappedValue: model) }\n', 1)
        chunks += ['\n// Variant: ' + name + '\n', body]
        manifest['variants'][name] = {'type': typename, 'sections': [labels[i] for i in selected],
                                     'retains_full_source_layout': name == 'full'}
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

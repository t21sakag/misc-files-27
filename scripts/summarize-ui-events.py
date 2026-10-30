#!/usr/bin/env python3
"""Export numeric XCTest pointer events without strings, keys or object decoding."""
import argparse
import json
import math
from pathlib import Path
import plistlib


def decode(data):
    if len(data) > 65536:
        raise ValueError('Event record exceeds 64 KiB')
    archive = plistlib.loads(data)
    objects = archive['$objects']
    if len(objects) > 4096:
        raise ValueError('Too many archived objects')
    def ref(value):
        if not isinstance(value, plistlib.UID) or value.data >= len(objects):
            raise ValueError('Invalid object reference')
        return objects[value.data]
    def number(value):
        value = ref(value)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError('Invalid event number')
        return value
    root = ref(archive['$top']['root'])
    result = []
    paths = ref(root['eventPaths'])['NS.objects']
    if len(paths) > 128:
        raise ValueError('Too many pointer paths')
    for path in paths:
        events = ref(ref(path)['pointerEvents'])['NS.objects']
        if len(result) + len(events) > 4096:
            raise ValueError('Too many pointer events')
        for event in events:
            value = ref(event)
            result.append({key: number(value[key]) for key in ['eventType', 'coordinate.x', 'coordinate.y', 'offset']})
    return result


def summarize(directory):
    directory = directory.resolve()
    result = {'records': [], 'errors': [], 'truncated': False}
    total_events = 0
    try:
        manifest = directory/'manifest.json'
        if manifest.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('Manifest exceeds 2 MiB')
        groups = json.loads(manifest.read_text())
        for group in groups:
            for entry in group.get('attachments', []):
                if not entry.get('suggestedHumanReadableName', '').startswith('Synthesized Event '):
                    continue
                if len(result['records']) + len(result['errors']) >= 512:
                    result['truncated'] = True
                    return result
                name = entry['exportedFileName']
                if not isinstance(name, str) or Path(name).name != name or name in ('', '.', '..'):
                    raise ValueError('Invalid event filename')
                source = directory/name
                try:
                    if source.is_symlink() or source.stat().st_size > 65536:
                        raise ValueError('Invalid event file')
                    events = decode(source.read_bytes())
                    if total_events + len(events) > 8192:
                        result['truncated'] = True
                        return result
                    total_events += len(events)
                    result['records'].append({'file': name, 'events': events})
                except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError, plistlib.InvalidFileException):
                    result['errors'].append({'file': name, 'reason': 'Unreadable or unsupported event record'})
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        result['errors'].append({'reason': 'Unreadable or unsupported attachment manifest'})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = summarize(args.directory)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print('Input diagnostics:', len(report['records']), 'records,', len(report['errors']), 'errors')


if __name__ == '__main__':
    main()

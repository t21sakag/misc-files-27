#!/usr/bin/env python3
"""Preserve mtimes only for byte-identical Xcode inputs from a successful build.

Git checkout and xcodegen otherwise replace mtimes on every CI runner. A content
hash is mandatory: changed files must keep their new mtime and rebuild normally.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def inputs(root):
    # Include every Apple target and shared source, not only the original app.
    # A new extension must not silently fall outside incremental compilation.
    for folder in ('ios', 'build/native/iphonesimulator'):
        for path in sorted((root / folder).rglob('*')):
            if path.is_file() and not path.is_symlink() and 'xcuserdata' not in path.parts:
                yield path
    for path in sorted((root / 'build').glob('*-Info.plist')):
        if path.is_file() and not path.is_symlink():
            yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('save', 'restore'))
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--manifest', type=Path, default=Path('build/simulator/input-mtimes.json'))
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = args.manifest
    if args.mode == 'save':
        records = {str(path.relative_to(root)): {'sha256': digest(path), 'mtime_ns': path.stat().st_mtime_ns}
                   for path in inputs(root)}
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps({'version': 1, 'inputs': records}, sort_keys=True) + '\n')
        print(f'Saved {len(records)} input timestamps')
        return
    if not manifest.exists():
        print('No previous input timestamps; cold build')
        return
    previous = json.loads(manifest.read_text())
    if previous.get('version') != 1:
        raise SystemExit('Unknown input timestamp manifest version')
    restored = changed = 0
    # Enumerate local inputs, never trust cached paths for filesystem writes.
    for path in inputs(root):
        record = previous['inputs'].get(str(path.relative_to(root)))
        if record and record['sha256'] == digest(path):
            os.utime(path, ns=(path.stat().st_atime_ns, record['mtime_ns']))
            restored += 1
        else:
            changed += 1
    print(f'Restored {restored} identical input timestamps; {changed} changed/new inputs remain invalidated')


if __name__ == '__main__':
    main()

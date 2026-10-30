#!/usr/bin/env python3
"""Hash explicit build inputs without walking restored native/Xcode outputs.

Matches hashFiles' SHA256 of the concatenated per-file SHA256 digests,
using pattern order and lexicographic traversal within the source directory.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ['native/Cargo.lock', 'native/Cargo.toml', 'native/build.rs',
          'scripts/build-native.sh', 'rust-toolchain.toml']
CARGO = ['native/Cargo.lock', 'native/Cargo.toml', 'native/build.rs', '.gitmodules']


def digest(root, names):
    paths = list(dict.fromkeys(names))
    result = hashlib.sha256()
    for name in paths:
        path = root / name
        if not path.is_file():
            raise FileNotFoundError(path)
        result.update(hashlib.sha256(path.read_bytes()).digest())
    return result.hexdigest()


def hashes(root):
    sources = sorted(p.relative_to(root).as_posix() for p in (root / 'native/src').rglob('*') if p.is_file())
    if not sources:
        raise RuntimeError('Missing native source inputs')
    return {
        'bridge': digest(root, sources + BRIDGE),
        'cargo': digest(root, CARGO),
        'simulator': digest(root, sources + BRIDGE + ['ios/project.yml']),
        'apple_targets': digest(root, ['ios/project.yml']),
    }


if __name__ == '__main__':
    for key, value in hashes(ROOT).items():
        print(f'{key}={value}')

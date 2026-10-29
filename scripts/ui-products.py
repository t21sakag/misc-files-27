#!/usr/bin/env python3
"""Preserve signed products/symlinks and bind transfers to source and toolchain."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tarfile

ap = argparse.ArgumentParser()
ap.add_argument('action', choices=['pack', 'unpack'])
ap.add_argument('--source', required=True)
args = ap.parse_args()
archive = Path('build/ui-products.tar.gz')
manifest = Path('build/ui-products.json')
workspace = str(Path.cwd())
toolchain = subprocess.check_output(['xcodebuild', '-version'], text=True)
if args.action == 'pack':
    paths = ['build/simulator/Build/Products', 'build/native/host', 'build/fixture.apkg', 'build/ui-batches.json']
    assert len(list(Path(paths[0]).glob('*.xctestrun'))) == 1
    with tarfile.open(archive, 'w:gz') as tar:
        for name in paths:
            tar.add(name)
    manifest.write_text(json.dumps({'source': args.source, 'toolchain': toolchain,
        'workspace': workspace, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}, indent=2)+'\n')
else:
    data = json.loads(manifest.read_text())
    assert data['source'] == args.source and data['toolchain'] == toolchain
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == data['sha256']
    with tarfile.open(archive) as tar:
        base = Path.cwd().resolve()
        for member in tar:
            target = base/member.name
            assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
            assert target.resolve().is_relative_to(base)
            assert member.isfile() or member.isdir() or member.issym() or member.islnk()
            if member.issym() or member.islnk():
                link = (target.parent if member.issym() else base)/member.linkname
                assert not Path(member.linkname).is_absolute() and link.resolve().is_relative_to(base)
            member.mode &= 0o755
            member.uid = member.gid = member.uname = member.gname = None
            tar.extract(member, path=base)
    def relocate(value):
        if isinstance(value, dict): return {k: relocate(v) for k, v in value.items()}
        if isinstance(value, list): return [relocate(v) for v in value]
        if isinstance(value, str) and value.startswith(data['workspace']+'/'):
            return workspace+value[len(data['workspace']):]
        return value
    for run in Path('build/simulator/Build/Products').glob('*.xctestrun'):
        run.write_bytes(plistlib.dumps(relocate(plistlib.loads(run.read_bytes()))))
print(args.action, 'bytes=', archive.stat().st_size, 'sha256=', hashlib.sha256(archive.read_bytes()).hexdigest())

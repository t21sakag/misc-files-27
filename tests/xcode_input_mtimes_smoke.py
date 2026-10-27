"""A restored cache may reuse timestamps only when input bytes are identical."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

script = Path('scripts/xcode-input-mtimes.py').resolve()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    folder = root / 'ios/AnkiPad'
    folder.mkdir(parents=True)
    same = folder / 'Same.swift'
    changed = folder / 'Changed.swift'
    same.write_text('let a = 1\n')
    changed.write_text('let b = 1\n')
    baseline = 1_600_000_000_000_000_000
    for path in (same, changed):
        os.utime(path, ns=(baseline, baseline))
    manifest = root / 'timestamps.json'
    def run(mode):
        subprocess.run(['python3', str(script), mode, '--root', str(root), '--manifest', str(manifest)], check=True)
    run('save')
    changed.write_text('let b = 2\n')
    changed_time = changed.stat().st_mtime_ns
    os.utime(same, ns=(baseline + 100_000_000, baseline + 100_000_000))
    new = folder / 'New.swift'
    new.write_text('let c = 1\n')
    new_time = new.stat().st_mtime_ns
    records = json.loads(manifest.read_text())
    records['inputs']['../../outside'] = {'sha256': 'x', 'mtime_ns': 0}
    manifest.write_text(json.dumps(records))
    run('restore')
    assert same.stat().st_mtime_ns == baseline
    assert changed.stat().st_mtime_ns == changed_time
    assert new.stat().st_mtime_ns == new_time
print('PASS: identical files reuse timestamps; changed/new files rebuild; cached paths cannot escape input roots')

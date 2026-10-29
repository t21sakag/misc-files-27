#!/usr/bin/env python3
"""Own a fresh test device; never erase or remove preexisting simulators."""
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

manifest = Path('build/ci-simulator.json')
def simctl(*args):
    return subprocess.check_output(['xcrun', 'simctl', *args], text=True).strip()

def create():
    if manifest.exists():
        raise SystemExit('A device lease already exists; refusing to create a duplicate')
    inventory = json.loads(simctl('list', 'devices', 'available', '-j'))
    selected = subprocess.check_output([sys.executable, str(Path(__file__).with_name('select-ipad-simulator.py'))],
                                       input=json.dumps(inventory), text=True).strip()
    runtime, template = next((runtime, device) for runtime, devices in inventory['devices'].items()
                             for device in devices if device['udid'] == selected)
    if template['state'] == 'Booted':
        simctl('shutdown', selected)  # Preserve its data; avoid two running iPads.
    name = 'Checks-' + os.environ.get('GITHUB_RUN_ID', 'local') + '-' + uuid.uuid4().hex[:12]
    device = simctl('create', name, template['deviceTypeIdentifier'], runtime)
    uuid.UUID(device)
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({'id': device, 'name': name, 'runtime': runtime}) + '\n')
    print(device)

def delete():
    if not manifest.exists():
        return
    lease = json.loads(manifest.read_text())
    uuid.UUID(lease['id'])
    if not lease['name'].startswith('Checks-'):
        raise SystemExit('Unrecognized device lease; refusing cleanup')
    inventory = json.loads(simctl('list', 'devices', '-j'))
    existing = [d for ds in inventory['devices'].values() for d in ds if d['udid'] == lease['id']]
    if existing:
        device, = existing
        if device['name'] != lease['name']:
            raise SystemExit('Device name does not match lease; refusing cleanup')
        if device['state'] != 'Shutdown':
            simctl('shutdown', lease['id'])
        simctl('delete', lease['id'])
    manifest.unlink()

if sys.argv[1:] == ['create']:
    create()
elif sys.argv[1:] == ['delete']:
    delete()
else:
    raise SystemExit('Usage: ci-simulator.py create|delete')

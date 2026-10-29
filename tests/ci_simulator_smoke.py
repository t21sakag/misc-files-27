"""Check ownership and refusal paths without touching a developer's devices."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
script = root / 'scripts/ci-simulator.py'
template_id = '00000000-0000-4000-8000-000000000001'
owned_id = '00000000-0000-4000-8000-000000000002'
runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
template = {'udid': template_id, 'deviceTypeIdentifier': 'type.ipad', 'isAvailable': True,
            'name': 'iPad (A16)', 'state': 'Booted'}
inventory = {'devices': {runtime: [template]}}
original = subprocess.check_output
commands = []
def execute(args, **kwargs):
    if args[0] != 'xcrun':
        return original(args, **kwargs)
    commands.append(args)
    operation = args[2]
    if operation == 'list': return json.dumps(inventory)
    if operation == 'create':
        assert args[4:] == ['type.ipad', runtime]
        inventory['devices'][runtime].append({'udid': owned_id, 'name': args[3], 'state': 'Booted'})
        return owned_id
    if operation == 'shutdown' and args[3:] == [template_id]:
        return ''
    assert args[3:] == [owned_id], args
    if operation == 'delete': inventory['devices'][runtime].pop()
    else: assert operation == 'shutdown', args
    return ''
def run(action):
    with patch.object(sys, 'argv', [str(script), action]), redirect_stdout(io.StringIO()) as output:
        runpy.run_path(str(script), run_name='__main__')
    return output.getvalue().strip()
with tempfile.TemporaryDirectory() as temp, patch('subprocess.check_output', side_effect=execute):
    previous = Path.cwd()
    try:
        os.chdir(temp)
        assert run('create') == owned_id
        lease = Path('build/ci-simulator.json')
        assert lease.exists()
        before = len(commands)
        try: run('create'); raise AssertionError('Duplicate was created')
        except SystemExit: pass
        assert len(commands) == before
        inventory['devices'][runtime][-1]['name'] = 'Someone else'
        try: run('delete'); raise AssertionError('Foreign device was removed')
        except SystemExit: pass
        assert all(c[2] != 'delete' and (c[2] != 'shutdown' or c[3] == template_id) for c in commands)
        inventory['devices'][runtime][-1]['name'] = json.loads(lease.read_text())['name']
        run('delete')
        assert not lease.exists() and inventory['devices'][runtime] == [template]
        before = len(commands); run('delete'); assert len(commands) == before
    finally: os.chdir(previous)
print('PASS: fresh iPadOS 27 selection, unique owned device, duplicate refusal, foreign-device cleanup refusal and owned cleanup only')

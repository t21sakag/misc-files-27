"""Exercise planning and actual tar/plist transfer in a different workspace."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('planner', root/'scripts/plan-ui-batches.py')
planner = importlib.util.module_from_spec(spec); spec.loader.exec_module(planner)
groups = json.loads((root/'scripts/ui-case-groups.json').read_text())
durations = json.loads((root/'scripts/ui-case-durations.json').read_text())
result = planner.plan(groups, durations)
expected = sorted(c+'/'+m for c, ms in groups.items() for m in ms)
assert sorted(c for b in result['batches'] for c in b) == expected
assert all(result['batches']) and len(result['batches']) == 3
assert result == planner.plan(groups, durations), 'Non-deterministic scope'
assert sum(map(len, planner.plan(groups, durations, True)['batches'])) == 2
changed = dict(groups, NewTests=['testNewFeature'])
assert 'NewTests/testNewFeature' in sum(planner.plan(changed, durations)['batches'], [])

with tempfile.TemporaryDirectory() as directory:
    base = Path(directory); a = base/'producer'; b = base/'consumer'; tools = base/'tools'
    a.mkdir(); b.mkdir(); tools.mkdir()
    fake = tools/'xcodebuild'; fake.write_text('#!/bin/sh\nprintf "Xcode 27\\nBuild fake\\n"\n'); fake.chmod(0o755)
    env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'])
    products = a/'build/simulator/Build/Products'; products.mkdir(parents=True)
    binary = products/'App.app/App'; binary.parent.mkdir(); binary.write_bytes(b'compiled contents'); binary.chmod(0o755)
    (products/'AppLink').symlink_to('App.app')
    run = {'TestTargets': [{'TestBundlePath': str(binary), 'Root': '__TESTROOT__/App.app'}]}
    (products/'tests.xctestrun').write_bytes(plistlib.dumps(run))
    (a/'build/native/host').mkdir(parents=True)
    (a/'build/native/host/server').write_bytes(b'host')
    (a/'build/fixture.apkg').write_bytes(b'synthetic package')
    (a/'build/ui-batches.json').write_text(json.dumps(result))
    settings={'targets':[{'target':'StudyWidgets','PRODUCT_BUNDLE_IDENTIFIER':'com.fixture.widgets'}]}
    (a/'build/project-settings.json').write_text(json.dumps(settings))
    fixture=products/'App.app/PlugIns/Tests.xctest/ReceivedFixtures/preview.apkg'
    fixture.parent.mkdir(parents=True);fixture.write_bytes(b'compiled test resource')
    script = str(root/'scripts/ui-products.py')
    subprocess.run(['python3', script, 'pack', '--source', 'abc'], cwd=a, env=env, check=True, stdout=subprocess.DEVNULL)
    import shutil
    shutil.copytree(a/'build', b/'build', ignore=shutil.ignore_patterns('simulator','native','fixture.apkg','ui-batches.json'))
    rejected = subprocess.run(['python3', script, 'unpack', '--source', 'wrong'], cwd=b, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert rejected.returncode != 0 and not (b/'build/simulator').exists()
    subprocess.run(['python3', script, 'unpack', '--source', 'abc'], cwd=b, env=env, check=True, stdout=subprocess.DEVNULL)
    out = b/'build/simulator/Build/Products'
    assert json.loads((b/'build/project-settings.json').read_text())==settings
    assert (out/'App.app/PlugIns/Tests.xctest/ReceivedFixtures/preview.apkg').read_bytes()==b'compiled test resource'
    assert (out/'App.app/App').read_bytes() == binary.read_bytes()
    assert os.access(out/'App.app/App', os.X_OK) and (out/'AppLink').is_symlink()
    restored = plistlib.loads((out/'tests.xctestrun').read_bytes())
    assert Path(restored['TestTargets'][0]['TestBundlePath']).resolve() == (out/'App.app/App').resolve()
    assert restored['TestTargets'][0]['Root'] == '__TESTROOT__/App.app'
    archive = b/'build/ui-products.tar.gz'; archive.write_bytes(archive.read_bytes()+b'corrupt')
    rejected = subprocess.run(['python3', script, 'unpack', '--source', 'abc'], cwd=b, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert rejected.returncode != 0
print('PASS: complete/disjoint/stable batches, new-case inclusion, compiled fixture/settings/binary/symlink/mode preservation, path relocation, source and digest rejection')

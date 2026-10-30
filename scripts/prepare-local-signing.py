#!/usr/bin/env python3
"""Preserve shared-container declarations for a later SideStore team signature.

No signing identity, account credentials or provisioning profile is used here.
The ad-hoc signatures only carry entitlements and check local bundle integrity.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import importlib.util
_spec = importlib.util.spec_from_file_location('macho_entitlements', Path(__file__).with_name('macho_entitlements.py'))
_macho = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_macho)
device_executable, xml_entitlements = _macho.device_executable, _macho.xml_entitlements

parser = argparse.ArgumentParser()
parser.add_argument('app',type=Path)
args = parser.parse_args()
app = args.app.resolve()
def info(bundle):
    return plistlib.loads((bundle/'Info.plist').read_bytes())
main = info(app)
plugins = list((app/'PlugIns').glob('*.appex'))
assert {info(plugin)['CFBundleIdentifier'] for plugin in plugins} == {main['CFBundleIdentifier']+suffix for suffix in ['.share','.widgets']}
assert len(plugins) == 2
group = main['StudySharedGroup']
assert group == 'group.'+main['CFBundleIdentifier']+'.shared'
assert all(info(plugin)['StudySharedGroup'] == group for plugin in plugins)
assert not list(app.rglob('embedded.mobileprovision'))
report_path=Path('build/delivery-inspection.json')
report_path.parent.mkdir(parents=True,exist_ok=True)
report={'bundles':[{key:info(bundle).get(key) for key in ['CFBundleIdentifier','CFBundleVersion','AnkiPadSourceCommit','UIDeviceFamily','MinimumOSVersion','StudySharedGroup']} for bundle in [app]+plugins], 'os_signature_verified':False}
report_path.write_text(json.dumps(report,indent=2)+'\n')
def sign(path, entitlements=None):
    command = ['codesign','--force','--sign','-','--timestamp=none','--generate-entitlement-der']
    if entitlements: command += ['--entitlements',str(entitlements)]
    subprocess.run(command+[str(path)],check=True)
with tempfile.TemporaryDirectory(prefix='LocalSigning-') as directory:
    entitlement_file = Path(directory)/'groups.plist'
    entitlement_file.write_bytes(plistlib.dumps({'com.apple.security.application-groups':[group]}))
    for library in sorted(app.rglob('*.dylib')): sign(library)
    for framework in sorted(app.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True): sign(framework)
    for bundle in plugins+[app]:
        executable = bundle/info(bundle)['CFBundleExecutable']
        device_executable(executable.read_bytes())
        sign(bundle,entitlement_file)
        assert xml_entitlements(executable.read_bytes())['com.apple.security.application-groups'] == [group]
    subprocess.run(['codesign','--verify','--strict','--deep',str(app)],check=True)
report['os_signature_verified']=True
report_path.write_text(json.dumps(report,indent=2)+'\n')
print('PASS: local ad-hoc app/extension signatures preserve matching shared-container declarations; no account/profile used')

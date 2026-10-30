#!/usr/bin/env python3
"""Preserve shared-container declarations for a later SideStore team signature.

No signing identity, account credentials or provisioning profile is used here.
The ad-hoc signatures only carry entitlements and check local bundle integrity.
"""
import argparse
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
assert len(plugins) == 1 and info(plugins[0])['CFBundleIdentifier'] == main['CFBundleIdentifier']+'.share'
group = main['StudySharedGroup']
assert group == 'group.'+main['CFBundleIdentifier']+'.shared'
assert info(plugins[0])['StudySharedGroup'] == group
assert not list(app.rglob('embedded.mobileprovision'))
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
print('PASS: local ad-hoc app/extension signatures preserve matching shared-container declarations; no account/profile used')

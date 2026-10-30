#!/usr/bin/env python3
"""Inspect generated Apple target settings before native builds or UI runs."""
import argparse
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--output',type=Path,default=Path('build/project-settings.json'))
parser.add_argument('--check',action='store_true')
args = parser.parse_args()
root=Path(__file__).resolve().parents[1]
subprocess.run(['xcodegen','generate'],cwd=root/'ios',check=True)
raw=subprocess.check_output(['xcodebuild','-project','AnkiPad.xcodeproj','-alltargets','-configuration','Release','-sdk','iphoneos','-showBuildSettings','-json'],cwd=root/'ios',text=True)
targets=[]
keys=['PRODUCT_BUNDLE_IDENTIFIER','TARGETED_DEVICE_FAMILY','IPHONEOS_DEPLOYMENT_TARGET','STUDY_SHARED_GROUP','CODE_SIGN_ENTITLEMENTS','APPLICATION_EXTENSION_API_ONLY','OTHER_LDFLAGS','SWIFT_OBJC_BRIDGING_HEADER']
for target in json.loads(raw):
    if target['target'] not in ['AnkiPad','ShareExtension']:continue
    settings=target['buildSettings']
    value={'target':target['target'],**{key:settings.get(key) for key in keys}}
    previous=next((entry for entry in targets if entry['target']==target['target']),None)
    if previous is not None:
        assert previous==value, f"Conflicting duplicate target settings: {target['target']}"
    else: targets.append(value)
report={'source':os.environ.get('GITHUB_SHA'),'sdk':'iphoneos','configuration':'Release','targets':targets}
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
assert {target['target'] for target in targets} == {'AnkiPad','ShareExtension'},'Expected app and share targets'
if args.check:
    for target in targets:
        assert target['TARGETED_DEVICE_FAMILY'] == '2', f"Unexpected device family: {target}"
        assert target['IPHONEOS_DEPLOYMENT_TARGET'] == '18.0', f"Unexpected deployment target: {target}"
        assert target['STUDY_SHARED_GROUP'] and '$(' not in target['STUDY_SHARED_GROUP'], f"Unresolved shared group: {target}"
    share=next(target for target in targets if target['target']=='ShareExtension')
    assert share['APPLICATION_EXTENSION_API_ONLY']=='YES'
    assert 'ankipad_bridge' not in (share['OTHER_LDFLAGS'] or '')
    assert not share['SWIFT_OBJC_BRIDGING_HEADER']
    print('PASS: generated app/extension family, minimum OS, shared group and independent linking')

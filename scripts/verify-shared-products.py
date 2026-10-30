#!/usr/bin/env python3
"""Inspect the real embedded, signed simulator extension after an Apple build."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--source', required=True)
args = parser.parse_args()
def info(bundle):
    return plistlib.loads((bundle/'Info.plist').read_bytes())
def entitlements(bundle):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], check=True, capture_output=True)
    return plistlib.loads(result.stdout)
app = info(args.app)
extensions = list((args.app/'PlugIns').glob('*.appex'))
assert len(extensions) == 1, extensions
extension = extensions[0]
share = info(extension)
assert share['CFBundleIdentifier'] == app['CFBundleIdentifier']+'.share'
assert share['AnkiPadSourceCommit'] == app['AnkiPadSourceCommit'] == args.source
assert share['CFBundleVersion'] == app['CFBundleVersion']
assert share['CFBundleShortVersionString'] == app['CFBundleShortVersionString']
assert share['CFBundlePackageType'] == 'XPC!'
assert share['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.share-services'
assert share['NSExtension']['NSExtensionPrincipalClass'].endswith('.ShareViewController')
rule = share['NSExtension']['NSExtensionAttributes']['NSExtensionActivationRule']
assert rule['NSExtensionActivationSupportsText'] is True
assert rule['NSExtensionActivationSupportsWebURLWithMaxCount'] == 1
for bundle, value in [(args.app,app),(extension,share)]:
    assert value['StudySharedGroup'] == app['StudySharedGroup'] and '$(' not in value['StudySharedGroup']
    assert entitlements(bundle)['com.apple.security.application-groups'] == [app['StudySharedGroup']]
    assert (bundle/value['CFBundleExecutable']).is_file()
    for language in ['ja','en']:
        assert (bundle/(language+'.lproj')/'Localizable.strings').is_file()
    subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
assert not list(extension.rglob('*.anki2'))
assert not list(extension.rglob('*.apkg'))
assert not list(extension.rglob('backend'))
print('PASS: embedded share service, principal class, activation, source/version, localized resources and matching real signed group entitlements')

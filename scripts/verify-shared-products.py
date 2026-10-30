#!/usr/bin/env python3
"""Inspect the real embedded, signed simulator extension after an Apple build."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import struct

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--source', required=True)
args = parser.parse_args()
def info(bundle):
    return plistlib.loads((bundle/'Info.plist').read_bytes())
def entitlements(bundle):
    # Xcode places simulator entitlements in __TEXT,__entitlements. The
    # ad-hoc code signature itself correctly has an empty entitlement plist.
    # Debug builds may load application code from the adjacent debug dylib.
    candidates = [bundle/info(bundle)['CFBundleExecutable'], *bundle.glob('*.debug.dylib')]
    groups = []
    for binary in candidates:
        data = binary.read_bytes()
        assert data[:4] == b'\xcf\xfa\xed\xfe'
        count, size = struct.unpack_from('<II', data, 16)
        position, end = 32, 32+size
        assert end <= len(data)
        for _ in range(count):
            command, length = struct.unpack_from('<II', data, position)
            assert length >= 8 and position+length <= end
            if command == 0x19:  # LC_SEGMENT_64; public mach-o/loader.h.
                assert length >= 72
                sections = struct.unpack_from('<I', data, position+64)[0]
                assert 72+80*sections <= length
                for index in range(sections):
                    section = position+72+80*index
                    name, segment = struct.unpack_from('<16s16s', data, section)
                    if name.rstrip(b'\0') == b'__entitlements' and segment.rstrip(b'\0') == b'__TEXT':
                        size, offset = struct.unpack_from('<QI', data, section+40)
                        assert 0 < size <= len(data)-offset
                        value = plistlib.loads(data[offset:offset+size])
                        groups.append(value['com.apple.security.application-groups'])
            position += length
        assert position == end
    assert groups, 'Simulator entitlement section missing: '+str(bundle)
    assert all(value == groups[0] for value in groups), 'Inconsistent simulator entitlement sections'
    return {'com.apple.security.application-groups':groups[0]}
app = info(args.app)
extensions = list((args.app/'PlugIns').glob('*.appex'))
assert {extension.name for extension in extensions} == {'ShareExtension.appex','StudyWidgets.appex'}, extensions
extension = next(extension for extension in extensions if extension.name == 'ShareExtension.appex')
share = info(extension)
widget = next(extension for extension in extensions if extension.name == 'StudyWidgets.appex')
widget_info = info(widget)
assert widget_info['CFBundleIdentifier'] == app['CFBundleIdentifier']+'.widgets'
assert widget_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
assert 'NSExtensionPrincipalClass' not in widget_info['NSExtension']
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
for key in ['File', 'Image', 'Movie']:
    assert rule['NSExtensionActivationSupports'+key+'WithMaxCount'] == 1
for bundle, value in [(args.app,app), *[(extension, info(extension)) for extension in extensions]]:
    assert value['AnkiPadSourceCommit'] == args.source
    assert value['CFBundleVersion'] == app['CFBundleVersion']
    assert value['CFBundleShortVersionString'] == app['CFBundleShortVersionString']
    assert value['CFBundlePackageType'] == ('APPL' if bundle == args.app else 'XPC!')
    assert value['UIDeviceFamily']==[2] and value['MinimumOSVersion']=='18.0', (bundle,value.get('UIDeviceFamily'),value.get('MinimumOSVersion'))
    assert value['StudySharedGroup'] == app['StudySharedGroup'] and '$(' not in value['StudySharedGroup']
    assert entitlements(bundle)['com.apple.security.application-groups'] == [app['StudySharedGroup']]
    assert (bundle/value['CFBundleExecutable']).is_file()
    for language in ['ja','en']:
        assert (bundle/(language+'.lproj')/'Localizable.strings').is_file()
    subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
for extension in extensions:
    assert not list(extension.rglob('*.anki2'))
    assert not list(extension.rglob('*.apkg'))
    assert not list(extension.rglob('backend'))
for language in ['ja','en']:
    assert (widget/(language+'.lproj')/'WidgetConfiguration.strings').is_file()
print('PASS: embedded share/widget services, activation, source/version, localized resources and matching embedded simulator group entitlements and valid signatures')

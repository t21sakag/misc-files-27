#!/usr/bin/env python3
"""Verify the actual deliverable before publishing a CI artifact."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile
import importlib.util
_spec = importlib.util.spec_from_file_location('macho_entitlements', Path(__file__).with_name('macho_entitlements.py'))
_macho = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_macho)
device_executable, xml_entitlements = _macho.device_executable, _macho.xml_entitlements

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=Path)
parser.add_argument('--source', required=True)
args = parser.parse_args()
with zipfile.ZipFile(args.ipa) as package:
    assert package.testzip() is None, 'Corrupt ZIP entry'
    names = package.namelist()
    assert len(names) == len(set(names)), 'Duplicate ZIP entry'
    assert all('..' not in PurePosixPath(name).parts and not name.startswith('/') for name in names), 'Unsafe archive path'
    forbidden = [name for name in names if name.lower().endswith(('.apk', '.apkg', '.colpkg', '.anki2', '.mobileprovision'))]
    assert not forbidden, f'Unexpected deck, APK, collection or provisioning profile: {forbidden}'
    manifests = [name for name in names if len(PurePosixPath(name).parts) == 3 and name.startswith('Payload/') and name.endswith('.app/Info.plist')]
    assert len(manifests) == 1, 'Expected exactly one application bundle'
    info = plistlib.loads(package.read(manifests[0]))
    assert info['CFBundleIdentifier'] == 'com.localtools.studyclient'
    assert info['CFBundlePackageType'] == 'APPL'
    assert info['UIDeviceFamily'] == [2], 'Expected iPad-only build'
    assert info['AnkiPadSourceCommit'] == args.source, 'IPA/source commit mismatch'
    assert info['MinimumOSVersion'] == '18.0'
    app = manifests[0].removesuffix('Info.plist')
    for name in ['AGPL-3.0.txt', 'AnkiDroid-GPL-3.0.txt', 'Anki-NOTICE.txt']:
        assert app + name in names, 'Missing bundled license: ' + name
    plugins = [name for name in names if name.startswith(app+'PlugIns/') and name.endswith('.appex/Info.plist')]
    share_manifest = app+'PlugIns/ShareExtension.appex/Info.plist'
    widget_manifest = app+'PlugIns/StudyWidgets.appex/Info.plist'
    assert set(plugins) == {share_manifest,widget_manifest} and len(plugins) == 2, 'Unexpected/missing app extension'
    extension_root = share_manifest.removesuffix('Info.plist')
    extension = plistlib.loads(package.read(share_manifest))
    widget_root = widget_manifest.removesuffix('Info.plist')
    widget = plistlib.loads(package.read(widget_manifest))
    assert widget['CFBundleIdentifier'] == info['CFBundleIdentifier']+'.widgets'
    assert widget['CFBundlePackageType'] == 'XPC!'
    assert widget['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    assert 'NSExtensionPrincipalClass' not in widget['NSExtension']
    for key in ['CFBundleVersion','CFBundleShortVersionString','AnkiPadSourceCommit']:
        assert widget[key] == info[key], ('Widget metadata mismatch', key)
    assert extension['CFBundlePackageType'] == 'XPC!'
    assert extension['CFBundleIdentifier'] == info['CFBundleIdentifier']+'.share'
    assert extension['CFBundleVersion'] == info['CFBundleVersion']
    assert extension['CFBundleShortVersionString'] == info['CFBundleShortVersionString']
    assert extension['AnkiPadSourceCommit'] == args.source
    service = extension['NSExtension']
    assert service['NSExtensionPointIdentifier'] == 'com.apple.share-services'
    assert service['NSExtensionPrincipalClass'] == 'ShareExtension.ShareViewController'
    activation = service['NSExtensionAttributes']['NSExtensionActivationRule']
    assert activation['NSExtensionActivationSupportsText'] is True
    assert all(activation['NSExtensionActivationSupports'+kind+'WithMaxCount'] == 1 for kind in ['File','Image','Movie','WebURL'])
    group = 'group.'+info['CFBundleIdentifier']+'.shared'
    for root, value in [(app,info),(extension_root,extension),(widget_root,widget)]:
        assert value['UIDeviceFamily'] == [2] and value['MinimumOSVersion'] == '18.0', f"{value['CFBundleIdentifier']}: device family={value['UIDeviceFamily']}, minimum OS={value['MinimumOSVersion']}"
        assert value.get('CFBundleSupportedPlatforms') == ['iPhoneOS']
        assert value['StudySharedGroup'] == group
        executable = package.read(root+value['CFBundleExecutable'])
        device_executable(executable)
        assert xml_entitlements(executable)['com.apple.security.application-groups'] == [group]
        for language in ['ja','en']:
            assert root+language+'.lproj/Localizable.strings' in names
        for marker in [b'ANKIPAD_UI_TEST_NAMESPACE',b'--uitest-',b'backend-theme-inspect',b'reminder-save-state',b'widget-snapshot-state']:
            assert marker not in executable, 'Release contains test hooks: '+repr(marker)
    for root in [extension_root,widget_root]:
        assert not any(name.startswith(root+'backend/') for name in names), 'Engine assets must remain in app'
    for language in ['ja','en']:
        assert widget_root+language+'.lproj/WidgetConfiguration.strings' in names
print(json.dumps({'source': args.source, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'bytes': args.ipa.stat().st_size, 'sha256': hashlib.sha256(args.ipa.read_bytes()).hexdigest(), 'iPad_ARM64': True, 'test_decks_absent': True, 'embedded_share_service': True, 'embedded_widgets': True, 'shared_group_declarations': True, 'release_test_hooks_absent': True}))

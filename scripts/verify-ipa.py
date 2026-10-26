#!/usr/bin/env python3
"""Verify the actual deliverable before publishing a CI artifact."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=Path)
parser.add_argument('--source', required=True)
args = parser.parse_args()
with zipfile.ZipFile(args.ipa) as package:
    assert package.testzip() is None, 'Corrupt ZIP entry'
    names = package.namelist()
    assert all('..' not in PurePosixPath(name).parts and not name.startswith('/') for name in names), 'Unsafe archive path'
    forbidden = [name for name in names if name.lower().endswith(('.apk', '.apkg', '.colpkg', '.anki2', '.mobileprovision'))]
    assert not forbidden, f'Unexpected deck, APK, collection or provisioning profile: {forbidden}'
    manifests = [name for name in names if len(PurePosixPath(name).parts) == 3 and name.startswith('Payload/') and name.endswith('.app/Info.plist')]
    assert len(manifests) == 1, 'Expected exactly one application bundle'
    info = plistlib.loads(package.read(manifests[0]))
    assert info['CFBundleIdentifier'] == 'com.localtools.studyclient'
    assert info['UIDeviceFamily'] == [2], 'Expected iPad-only build'
    assert info['AnkiPadSourceCommit'] == args.source, 'IPA/source commit mismatch'
    assert info['MinimumOSVersion'] == '18.0'
    app = manifests[0].removesuffix('Info.plist')
    for name in ['AGPL-3.0.txt', 'AnkiDroid-GPL-3.0.txt', 'Anki-NOTICE.txt']:
        assert app + name in names, 'Missing bundled license: ' + name
    executable = package.read(app + info['CFBundleExecutable'])
    assert executable[:4] == b'\xcf\xfa\xed\xfe', 'Expected a 64-bit Mach-O executable'
    assert int.from_bytes(executable[4:8], 'little') == 0x100000c, 'Expected ARM64 device executable'
    assert info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Expected a device application'
    command_count, command_bytes = struct.unpack_from('<II', executable, 16)
    position = 32
    commands_end = position + command_bytes
    assert commands_end <= len(executable), 'Truncated Mach-O load commands'
    platforms = []
    for _ in range(command_count):
        assert position + 8 <= commands_end, 'Missing Mach-O load command'
        command, length = struct.unpack_from('<II', executable, position)
        assert length >= 8 and position + length <= commands_end, 'Invalid Mach-O load command length'
        if command == 0x32:  # LC_BUILD_VERSION: arm64 simulators use platform 7.
            assert length >= 24, 'Truncated build platform metadata'
            platforms.append(struct.unpack_from('<I', executable, position + 8)[0])
        position += length
    assert position == commands_end and platforms == [2], 'Expected iOS device Mach-O, not simulator/macOS'
print(json.dumps({'source': args.source, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'bytes': args.ipa.stat().st_size, 'sha256': hashlib.sha256(args.ipa.read_bytes()).hexdigest(), 'iPad_ARM64': True, 'test_decks_absent': True}))

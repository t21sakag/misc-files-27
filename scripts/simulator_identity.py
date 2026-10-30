"""Validate a consistent simulator-only identity for OS extension services."""
import re


def validate(entitlements, bundle):
    team = entitlements.get('com.apple.developer.team-identifier', '')
    assert re.fullmatch(r'[A-Z0-9]{10}', team), 'Simulator identity needs a ten-character team prefix'
    identity = team + '.' + bundle
    assert entitlements.get('application-identifier') == identity, 'Simulator App ID does not match team and bundle'
    if 'keychain-access-groups' in entitlements:
        assert entitlements['keychain-access-groups'] == [identity], 'Simulator Keychain group does not match App ID'
    return team

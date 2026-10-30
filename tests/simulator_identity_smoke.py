#!/usr/bin/env python3
"""Reject malformed simulator identity templates before an Apple UI build."""
from copy import deepcopy
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from simulator_identity import validate

for name in ['Simulator.entitlements', 'ShareSimulator.entitlements']:
    raw = (ROOT/'ios'/name).read_text()
    for suffix in ([''] if name == 'Simulator.entitlements' else ['.share', '.widgets']):
        template = plistlib.loads(raw.encode())['application-identifier']
        bundle = template.split('.', 1)[1] if name == 'Simulator.entitlements' else 'org.example.studyclient'+suffix
        # The main template uses each repository's bundle ID; extensions use
        # PRODUCT_BUNDLE_IDENTIFIER. Both must resolve to a matching identity.
        expanded = raw.replace('$(PRODUCT_BUNDLE_IDENTIFIER)', bundle)
        entitlements = plistlib.loads(expanded.encode())
        assert validate(entitlements, bundle) == 'SIMULATOR0'
        for changes in [
            {'com.apple.developer.team-identifier': 'SIMULATOR'},
            {'application-identifier': 'SIMULATOR.'+bundle},
            {'application-identifier': 'SIMULATOR0.other.bundle'},
            {'com.apple.developer.team-identifier': ''},
            {'keychain-access-groups': ['SIMULATOR0.other.bundle']},
        ]:
            invalid = deepcopy(entitlements); invalid.update(changes)
            try:
                validate(invalid, bundle)
            except AssertionError:
                pass
            else:
                raise AssertionError('Accepted inconsistent simulator identity')
print('PASS: main/share/widget simulator identities match ten-character team, App ID and Keychain scope; malformed identities rejected')

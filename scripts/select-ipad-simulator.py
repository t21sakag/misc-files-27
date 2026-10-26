#!/usr/bin/env python3
"""Select the requested iPadOS generation; never silently test an older runtime."""
import json
import re
import sys

inventory = json.load(sys.stdin)
choices = []
for runtime, devices in inventory['devices'].items():
    version = re.search(r'\.iOS-(\d+)-(\d+)(?:-(\d+))?$', runtime)
    if not version or int(version[1]) != 27:
        continue
    for device in devices:
        if device.get('isAvailable', False) and device['name'].startswith('iPad'):
            choices.append((tuple(int(part or 0) for part in version.groups()), runtime, device))
if not choices:
    raise SystemExit('No available iPadOS 27 simulator; refusing to substitute an older runtime')
_, runtime, device = min(choices, key=lambda choice: (choice[0], choice[2]['name']))
print(json.dumps({'runtime': runtime, 'device': device['name'], 'udid': device['udid']}), file=sys.stderr)
print(device['udid'])

#!/usr/bin/env python3
"""Require read-only notification replies before a relocated native UI journey."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import time
import uuid


def run(simulator, app, output, timeout=120):
    simulator = str(uuid.UUID(simulator)).upper()
    namespace = str(uuid.uuid4()).upper()
    bundle = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
    if not isinstance(bundle, str) or not re.fullmatch(r'[A-Za-z0-9.-]+', bundle):
        raise ValueError('Invalid app bundle identity')
    report = {'version': 1, 'classification': 'environment', 'ready': False,
              'simulator': simulator, 'bundle': bundle, 'namespace': namespace,
              'permission_requested': False, 'requests_mutated': False}
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    launched = False
    def simctl(*args, **kwargs):
        return subprocess.run(['xcrun', 'simctl', *args], check=True,
                              capture_output=True, text=True, timeout=30, **kwargs)
    try:
        simctl('install', simulator, str(app))
        container = Path(simctl('get_app_container', simulator, bundle, 'data').stdout.strip())
        if not container.is_absolute():
            raise ValueError('App data container is not absolute')
        probe = container / 'Library/Application Support/UITests' / namespace / 'notification-service.json'
        env = dict(os.environ, SIMCTL_CHILD_ANKIPAD_UI_TEST_NAMESPACE=namespace)
        simctl('launch', simulator, bundle, '--uitest-notification-readiness', env=env)
        launched = True
        deadline = time.monotonic() + timeout
        while True:
            if probe.exists():
                if probe.stat().st_size > 4096:
                    raise ValueError('Oversized native service probe')
                native = json.loads(probe.read_text())
                if (native.get('version'), native.get('namespace'), native.get('bundle')) != (1, namespace, bundle):
                    raise ValueError('Native service probe identity mismatch')
                report['native'] = native
                if native.get('phase') == 'complete':
                    status, pending = native.get('authorizationStatus'), native.get('pendingCount')
                    if type(status) is not int or status not in range(5) or type(pending) is not int or pending < 0:
                        raise ValueError('Invalid native notification response')
                    report['ready'] = True
                    return report
                if native.get('phase') not in ('notificationSettings', 'pendingNotificationRequests'):
                    raise ValueError('Unknown native service phase')
            if time.monotonic() >= deadline:
                raise TimeoutError('Native notification service did not reply before UI')
            time.sleep(min(0.5, max(0, deadline - time.monotonic())))
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if launched:
            try:
                simctl('terminate', simulator, bundle)
                report['terminated'] = True
            except (subprocess.SubprocessError, OSError) as error:
                report['terminated'] = False
                report['termination_error'] = str(error)
                report['ready'] = False
        report['elapsed_seconds'] = round(time.monotonic() - started, 3)
        output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('build/notification-preflight.json'))
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    if not 0.1 <= args.timeout <= 120:
        parser.error('Service deadline must be between 0.1 and 120 seconds')
    result = run(args.simulator, args.app, args.output, args.timeout)
    if not result['ready']:
        raise SystemExit('Notification preflight cleanup failed')
    print('PASS: actual app notification service replied without permission/request mutations')

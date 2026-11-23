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


def run(simulator, app, output, timeout=180, max_attempts=None):
    simulator = str(uuid.UUID(simulator)).upper()
    attempt_count = (2 if timeout >= 30 else 1) if max_attempts is None else int(max_attempts)
    if not 1 <= attempt_count <= 2:
        raise ValueError('Max attempts must be 1 or 2')
    bundle = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
    if not isinstance(bundle, str) or not re.fullmatch(r'[A-Za-z0-9.-]+', bundle):
        raise ValueError('Invalid app bundle identity')
    report = {'version': 1, 'classification': 'environment', 'ready': False,
              'simulator': simulator, 'bundle': bundle, 'namespace': None,
              'permission_requested': False, 'requests_mutated': False, 'commands': [],
              'attempts': []}
    output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    launch_attempted = False
    def simctl(*args, **kwargs):
        report['phase'] = args[0]
        # Cold simulators finishing first-boot LaunchServices/SpringBoard migration
        # can exceed 120s on install and launch (observed 122.27s in 45116031376),
        # and exceed 30s on get_app_container and terminate.
        command_timeout = 240 if args[0] in ('install', 'launch') else 120
        command = {'operation': args[0], 'timeout_seconds': command_timeout}
        report['commands'].append(command)
        began = time.monotonic()
        try:
            result = subprocess.run(['xcrun', 'simctl', *args], check=True,
                                    capture_output=True, text=True, timeout=command_timeout, **kwargs)
            command['return_code'] = result.returncode
            return result
        except (subprocess.SubprocessError, OSError) as error:
            command['error_kind'] = type(error).__name__
            if isinstance(error, subprocess.CalledProcessError):
                command['return_code'] = error.returncode
            for name in ('stdout', 'stderr'):
                value = getattr(error, name, None)
                if value:
                    command[name] = (value.decode(errors='replace') if isinstance(value, bytes) else str(value))[-2048:]
            raise
        finally:
            command['elapsed_seconds'] = round(time.monotonic() - began, 3)
    try:
        simctl('install', simulator, str(app))
        for attempt in range(1, attempt_count + 1):
            namespace = str(uuid.uuid4()).upper()
            report['namespace'] = namespace
            report.pop('native', None)
            attempt_record = {'attempt': attempt, 'namespace': namespace, 'phase': 'launch'}
            report['attempts'].append(attempt_record)
            env = dict(os.environ, SIMCTL_CHILD_ANKIPAD_UI_TEST_NAMESPACE=namespace)
            # Start the actual readiness process before resolving its probe path.
            # A launch or container failure must still terminate that process.
            launch_attempted = True
            simctl('launch', simulator, bundle, '--uitest-notification-readiness', env=env)
            container = Path(simctl('get_app_container', simulator, bundle, 'data').stdout.strip())
            if not container.is_absolute():
                raise ValueError('App data container is not absolute')
            probe = container / 'Library/Application Support/UITests' / namespace / 'notification-service.json'
            report['phase'] = 'notification_service'
            attempt_record['phase'] = 'notification_service'
            attempt_deadline = time.monotonic() + (timeout / attempt_count)
            while True:
                if probe.exists():
                    if probe.stat().st_size > 4096:
                        raise ValueError('Oversized native service probe')
                    native = json.loads(probe.read_text())
                    if (native.get('version'), native.get('namespace'), native.get('bundle')) != (1, namespace, bundle):
                        raise ValueError('Native service probe identity mismatch')
                    report['native'] = native
                    attempt_record['native'] = native
                    if native.get('phase') == 'complete':
                        status, pending = native.get('authorizationStatus'), native.get('pendingCount')
                        if type(status) is not int or status not in range(5) or type(pending) is not int or pending < 0:
                            raise ValueError('Invalid native notification response')
                        attempt_record['phase'] = 'complete'
                        report['ready'] = True
                        return report
                    if native.get('phase') not in ('notificationSettings', 'pendingNotificationRequests'):
                        raise ValueError('Unknown native service phase')
                if time.monotonic() >= attempt_deadline:
                    attempt_record['timed_out'] = True
                    if attempt < attempt_count:
                        simctl('terminate', simulator, bundle)
                        launch_attempted = False
                        break
                    raise TimeoutError('Native notification service did not reply before UI')
                time.sleep(min(0.5, max(0, attempt_deadline - time.monotonic())))
    except Exception as error:
        report['error'] = str(error)
        report['error_kind'] = type(error).__name__
        report['failure_phase'] = report.get('phase')
        if report.get('phase') == 'terminate':
            report['terminated'] = False
            report['termination_error'] = str(error)
            launch_attempted = False
        raise
    finally:
        if launch_attempted:
            try:
                simctl('terminate', simulator, bundle)
                report['terminated'] = True
            except (subprocess.SubprocessError, OSError) as error:
                report['terminated'] = False
                report['termination_error'] = str(error)
                report.setdefault('failure_phase', 'terminate')
                report['ready'] = False
        report['phase'] = 'complete' if report['ready'] else 'failed'
        report['elapsed_seconds'] = round(time.monotonic() - started, 3)
        output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('build/notification-preflight.json'))
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--max-attempts', type=int, default=None)
    args = parser.parse_args()
    if not 0.1 <= args.timeout <= 240:
        parser.error('Service deadline must be between 0.1 and 240 seconds')
    if args.max_attempts is not None and not 1 <= args.max_attempts <= 2:
        parser.error('Max attempts must be 1 or 2')
    result = run(args.simulator, args.app, args.output, args.timeout, args.max_attempts)
    if not result['ready']:
        raise SystemExit('Notification preflight cleanup failed')
    print('PASS: actual app notification service replied without permission/request mutations')

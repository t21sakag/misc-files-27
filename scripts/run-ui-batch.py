#!/usr/bin/env python3
"""Execute transferred test products, then require the exact planned case count."""
import argparse
import json
import os
import plistlib
import uuid
import sys
from pathlib import Path
import subprocess

ap = argparse.ArgumentParser()
ap.add_argument('batch', type=int)
ap.add_argument('simulator')
ap.add_argument('--notification-timeout', type=float, default=120)
args = ap.parse_args()
if not 0.1 <= args.notification_timeout <= 120:
    ap.error("Notification deadline must be between 0.1 and 120 seconds")
plan = json.loads(Path('build/ui-batches.json').read_text())
cases = plan['batches'][args.batch]
assert cases and len(cases) == len(set(cases))
products = list(Path('build/simulator/Build/Products').glob('*.xctestrun'))
assert len(products) == 1, products
# Verify each consumer's own simulator and bundled data, not just the producer.
selections = Path('build/batch-ui-selections.txt')
selections.write_text(''.join('-only-testing:AnkiPadUITests/'+case+'\n' for case in cases))
prerequisites = [sys.executable, str(Path(__file__).with_name('ui-prerequisites.py')),
                 '--simulator', args.simulator, '--selections', str(selections)]
if any(case.endswith(('/testNotesPreviewUsesRepresentativesUntilMultipleRowsSelected',
                       '/testBrowserSelectionOrderSurvivesDeselectionAndReselection')) for case in cases):
    packages = [path for path in Path('build/simulator/Build/Products').rglob('preview.apkg')
                if path.parent.name == 'ReceivedFixtures']
    assert len(packages) == 1, ('Expected one compiled preview fixture', packages)
    prerequisites += ['--preview-package', str(packages[0])]
if any(case.startswith(('BrowserFieldSearchFlowTests/', 'BrowserSearchHistoryFlowTests/', 'BrowserSearchFiltersFlowTests/', 'BrowserSearchIdentityFlowTests/')) for case in cases):
    packages = [path for path in Path('build/simulator/Build/Products').rglob('field-search.apkg')
                if path.parent.name == 'ReceivedFixtures']
    assert len(packages) == 1, ('Expected one compiled field-search fixture', packages)
    prerequisites += ['--field-package', str(packages[0])]
if any(case.startswith('BrowserForgetFlowTests/') for case in cases):
    packages = [path for path in Path('build/simulator/Build/Products').rglob('browser-forget.apkg')
                if path.parent.name == 'ReceivedFixtures']
    assert len(packages) == 1, ('Expected one compiled reset fixture', packages)
    prerequisites += ['--reset-package', str(packages[0])]
subprocess.run(prerequisites, check=True)
notification_cases = {
    'NotificationAuthorizationFlowTests/testActualNotificationAuthorizationAndScheduleReplacement',
    'ReminderFlowTests/testReminderNativeSchedulePersistsReplacesAndCancels',
    'ConditionalReminderFlowTests/testConditionalDueThresholdCreatesDatedRequestsAndPreservesLegacyRepeatingMode',
    'ConditionalRefreshFlowTests/testScopedReminderRecomputesAfterActualReview',
}
preflight_code = None
deferred_cases = []
if notification_cases.intersection(cases):
    applications = list(Path('build/simulator/Build/Products').glob('Debug-iphonesimulator/AnkiPad.app'))
    assert len(applications) == 1, ('Expected one verified notification host', applications)
    probe_path = Path('build/notification-preflight.json')
    probe_path.unlink(missing_ok=True)
    preflight = subprocess.run([sys.executable, str(Path(__file__).with_name('run-ui-with-diagnostics.py')),
        '--simulator', args.simulator, '--output', 'build/notification-preflight-diagnostics', '--',
        sys.executable, str(Path(__file__).with_name('notification-preflight.py')),
        '--simulator', args.simulator, '--app', str(applications[0]),
        '--timeout', str(args.notification_timeout)])
    preflight_code = preflight.returncode
    if preflight_code != 0:
        # Only an actual OS-service timeout from the verified app identity,
        # followed by successful cleanup, is independent of other features.
        # Identity/corruption/install/launch/cleanup failures still block all UI.
        try:
            report = json.loads(probe_path.read_text())
            namespace = str(uuid.UUID(report['namespace'])).upper()
            bundle = plistlib.loads((applications[0]/'Info.plist').read_bytes())['CFBundleIdentifier']
            native = report['native']
            service_timeout = (report['version'] == 1 and report['ready'] is False
                and report['simulator'] == str(uuid.UUID(args.simulator)).upper()
                and report['bundle'] == bundle and report['terminated'] is True
                and report['permission_requested'] is False and report['requests_mutated'] is False
                and report['failure_phase'] == 'notification_service' and report['error_kind'] == 'TimeoutError'
                and native['version'] == 1 and native['namespace'] == namespace and native['bundle'] == bundle
                and native['phase'] in ('notificationSettings', 'pendingNotificationRequests'))
        except (OSError, ValueError, KeyError, TypeError):
            service_timeout = False
        if not service_timeout:
            raise subprocess.CalledProcessError(preflight_code, preflight.args)
        deferred_cases = [case for case in cases if case in notification_cases]
# A failed OS notification premise must block every dependent case, while
# unrelated cases still provide evidence. Deferral always fails this batch.
runnable_cases = [case for case in cases if case not in deferred_cases]
environment_report = {'version': 1, 'planned_cases': cases, 'requested_ui_cases': runnable_cases,
                      'deferred_cases': deferred_cases, 'notification_preflight_exit': preflight_code,
                      'phase': 'planned'}
report_path = Path('build/batch-environment.json')
report_path.write_text(json.dumps(environment_report, indent=2) + '\n')
if not runnable_cases:
    environment_report.update(phase='failed_environment', actual_cases=[])
    report_path.write_text(json.dumps(environment_report, indent=2) + '\n')
    raise SystemExit('Notification environment failed; no independent cases in this batch')
Path('build/batch-launch.json').write_text(json.dumps({'launcher': 'xctestrun',
    'source': os.environ.get('GITHUB_SHA'), 'cases': runnable_cases, 'planned_cases': cases,
    'deferred_cases': deferred_cases, 'compiles': False}, indent=2) + '\n')
result = subprocess.run([sys.executable, str(Path(__file__).with_name('run-ui-with-diagnostics.py')),
    '--simulator', args.simulator, '--',
    'xcodebuild', 'test-without-building', '-xctestrun', str(products[0]),
    '-destination', 'id='+args.simulator, '-parallel-testing-enabled', 'NO',
    '-resultBundlePath', 'build/UITests.xcresult',
    *['-only-testing:AnkiPadUITests/'+c for c in runnable_cases]])
subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', 'build/UITests.xcresult'],
               stdout=Path('build/test-summary.json').open('w'), check=True)
subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', 'build/UITests.xcresult'],
               stdout=Path('build/test-tree.json').open('w'), check=True)
summary = json.loads(Path('build/test-summary.json').read_text())
def identities(nodes):
    for node in nodes:
        if node.get('nodeType') == 'Test Case':
            yield node['nodeIdentifier'].removesuffix('()')
        yield from identities(node.get('children', []))
actual = list(identities(json.loads(Path('build/test-tree.json').read_text())['testNodes']))
environment_report.update(actual_cases=actual, xcode_return_code=result.returncode, phase='result_available')
report_path.write_text(json.dumps(environment_report, indent=2) + '\n')
assert sorted(actual) == sorted(runnable_cases), (actual, runnable_cases)
assert result.returncode == 0 and summary['totalTestCount'] == len(runnable_cases) and summary['passedTests'] == len(runnable_cases), summary
assert summary['failedTests'] == summary['skippedTests'] == 0, summary
assert summary.get('runtimeWarnings') == [], 'Runtime warnings require investigation before the batch can pass'

environment_report['phase'] = 'failed_environment' if deferred_cases else 'success'
report_path.write_text(json.dumps(environment_report, indent=2) + '\n')
assert not deferred_cases, ('Notification environment failed; dependent cases remain unexecuted', deferred_cases)

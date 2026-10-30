#!/usr/bin/env python3
"""Capture bounded widget logs from the owned test simulator after a UI run."""
import argparse
import json
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', default='')
parser.add_argument('--settings', type=Path, default=Path('build/project-settings.json'))
parser.add_argument('--output', type=Path, default=Path('build/widget-diagnostics'))
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
report = {'simulator': args.simulator, 'log_exit': None, 'log_timeout': False, 'crash_files': [], 'container_found': False, 'probe_found': False}
try:
    if args.simulator:
        simulator = str(uuid.UUID(args.simulator)).upper()
        settings = json.loads(args.settings.read_text())
        bundle = next(target['PRODUCT_BUNDLE_IDENTIFIER'] for target in settings['targets'] if target['target'] == 'StudyWidgets')
        assert re.fullmatch(r'[A-Za-z0-9.-]+', bundle) and bundle.endswith('.widgets')
        data = Path.home()/'Library/Developer/CoreSimulator/Devices'/simulator/'data'
        containers = [path for kind in ['PluginKitPlugin','Application'] for path in (data/'Containers/Data'/kind).glob('*')]
        for container in containers:
            metadata = container/'.com.apple.mobile_container_manager.metadata.plist'
            if not metadata.is_file() or metadata.is_symlink():
                continue
            try:
                identifier = plistlib.loads(metadata.read_bytes()).get('MCMMetadataIdentifier')
            except (OSError, plistlib.InvalidFileException):
                continue
            if identifier != bundle:
                continue
            report['container_found'] = True
            for relative in ['Library/Application Support/'+bundle+'-widget-probe.json', 'Library/Application Support/widget-probe.json', 'tmp/widget-probe.json']:
                probe = container/relative
                if probe.is_file() and not probe.is_symlink() and probe.stat().st_size <= 16384:
                    shutil.copy2(probe, args.output/'widget-probe.json')
                    report['probe_found'] = True
                    report['probe_location'] = relative
                    break
        # Simulator extension services may use the owned device's home instead
        # of a PluginKitPlugin home. The exact bundle-prefixed name prevents
        # another extension's probe from becoming evidence for this target.
        if not report['probe_found']:
            probe = data/'Library/Application Support'/(bundle+'-widget-probe.json')
            if probe.is_file() and not probe.is_symlink() and probe.stat().st_size <= 16384:
                shutil.copy2(probe, args.output/'widget-probe.json')
                report['probe_found'] = True
                report['probe_location'] = 'owned-device-home'
        predicate = 'process == "StudyWidgets" OR eventMessage CONTAINS ' + json.dumps(bundle)
        with (args.output/'system.log').open('w') as stream:
            try:
                result = subprocess.run(['xcrun', 'simctl', 'spawn', simulator, 'log', 'show', '--last', '5m', '--style', 'compact',
                    '--info', '--predicate', predicate], stdout=stream, stderr=subprocess.STDOUT, timeout=20)
                report['log_exit'] = result.returncode
            except subprocess.TimeoutExpired:
                report['log_timeout'] = True
        # Never walk host-wide crash reports or other simulators.
        crashes = data/'Library/Logs/CrashReporter'
        for path in sorted(crashes.glob('StudyWidgets*.ips'))[:5]:
            if not path.is_symlink() and path.stat().st_size <= 2 * 1024 * 1024:
                shutil.copy2(path, args.output/path.name)
                report['crash_files'].append(path.name)
    else:
        report['skipped'] = 'No owned simulator was prepared'
except Exception as error:
    report['diagnostic_error'] = str(error)
finally:
    (args.output/'collection.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))

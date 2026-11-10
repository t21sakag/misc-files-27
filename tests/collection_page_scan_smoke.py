"""Compile the production traversal state and verify bounded page coverage."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
swiftc = os.environ.get('ANKIPAD_SWIFTC') or shutil.which('swiftc')
assert swiftc, 'Swift compiler required for collection page checks'
with tempfile.TemporaryDirectory() as directory:
    binary = str(Path(directory)/'pages')
    subprocess.run([swiftc, '-swift-version', '5', '-parse-as-library',
        str(root/'ios/AnkiPadUITests/CollectionPageScanState.swift'),
        str(root/'tests/collection_page_scan_driver.swift'), '-o', binary], check=True, timeout=90)
    subprocess.run([binary], check=True, timeout=10)

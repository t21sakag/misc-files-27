"""Isolated local Chromium fixture for trusted-input tests; no user browser data."""
import contextlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request
import websocket

class Browser:
    def __init__(self, connection):
        self.connection = connection
        self.sequence = 0
    def call(self, method, params=None):
        self.sequence += 1
        self.connection.send(json.dumps({'id': self.sequence, 'method': method, 'params': params or {}}))
        while True:
            reply = json.loads(self.connection.recv())
            if reply.get('id') == self.sequence:
                if 'error' in reply:
                    raise RuntimeError(reply['error'])
                return reply.get('result', {})
    def evaluate(self, expression):
        result = self.call('Runtime.evaluate', {'expression': expression, 'returnByValue': True})
        if result.get('exceptionDetails'):
            raise RuntimeError(result['exceptionDetails'])
        return result['result'].get('value')
    def load(self, html):
        self.call('Page.enable')
        frame = self.call('Page.getFrameTree')['frameTree']['frame']['id']
        self.call('Page.setDocumentContent', {'frameId': frame, 'html': html})

@contextlib.contextmanager
def chromium():
    with tempfile.TemporaryDirectory(prefix='ankipad-local-browser-') as directory:
        with open(Path(directory) / 'browser.log', 'w') as log:
            process = subprocess.Popen(['chromium', '--headless', '--no-sandbox', '--disable-gpu',
                '--disable-background-networking', '--no-first-run', '--remote-debugging-address=127.0.0.1',
                '--remote-debugging-port=0', '--remote-allow-origins=*', '--user-data-dir=' + directory, 'about:blank'],
                stdout=log, stderr=log)
            connection = None
            try:
                port_file = Path(directory) / 'DevToolsActivePort'
                deadline = time.monotonic() + 20
                while not port_file.exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        log.flush()
                        raise RuntimeError((Path(directory) / 'browser.log').read_text()[-2000:])
                    time.sleep(0.1)
                port = int(port_file.read_text().splitlines()[0])
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/json') as response:
                    page = next(target for target in json.load(response) if target['type'] == 'page')
                connection = websocket.create_connection(page['webSocketDebuggerUrl'], timeout=10)
                yield Browser(connection)
            finally:
                if connection:
                    connection.close()
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()

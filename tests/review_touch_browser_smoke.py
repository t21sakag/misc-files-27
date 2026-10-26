"""Exercise the actual bridge with trusted input in local Chromium (not WebKit).
Requires chromium and Python websocket-client. Does not access user browser data.
"""
import json
import re
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
import websocket

source = Path('ios/AnkiPad/ReviewerWebView.swift').read_text()
script = re.search(r'static let reviewTapScript = #"""\n([\s\S]*?)\n\s*"""#', source)[1]
with tempfile.TemporaryDirectory(prefix='ankipad-touch-browser-') as directory:
    with open(Path(directory) / 'browser.log', 'w') as log:
        browser = subprocess.Popen(['chromium', '--headless', '--no-sandbox', '--disable-gpu',
            '--disable-background-networking', '--no-first-run', '--remote-debugging-address=127.0.0.1',
            '--remote-debugging-port=0', '--remote-allow-origins=*', '--user-data-dir=' + directory, 'about:blank'],
            stdout=log, stderr=log)
        connection = None
        try:
            port_file = Path(directory) / 'DevToolsActivePort'
            deadline = time.monotonic() + 20
            while not port_file.exists():
                if browser.poll() is not None or time.monotonic() > deadline:
                    log.flush()
                    raise RuntimeError('Chromium did not open its test debugging endpoint: ' + (Path(directory) / 'browser.log').read_text()[-2000:])
                time.sleep(0.1)
            port = int(port_file.read_text().splitlines()[0])
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/json') as response:
                targets = json.load(response)
            target = next(target for target in targets if target['type'] == 'page')
            connection = websocket.create_connection(target['webSocketDebuggerUrl'], timeout=10)
            request_id = 0
            def call(method, params=None):
                global request_id
                request_id += 1
                connection.send(json.dumps({'id': request_id, 'method': method, 'params': params or {}}))
                while True:
                    reply = json.loads(connection.recv())
                    if reply.get('id') == request_id:
                        if 'error' in reply:
                            raise RuntimeError(reply['error'])
                        return reply.get('result', {})
            def evaluate(expression):
                result = call('Runtime.evaluate', {'expression': expression, 'returnByValue': True})
                if result.get('exceptionDetails'):
                    raise RuntimeError(result['exceptionDetails'])
                return result['result'].get('value')
            def count():
                return evaluate('bridgeEvents.length')
            def click(x, y, clicks=1):
                for event_type in ['mousePressed', 'mouseReleased']:
                    call('Input.dispatchMouseEvent', {'type': event_type, 'x': x, 'y': y, 'button': 'left', 'clickCount': clicks})
            def settle():
                time.sleep(0.55)
            call('Page.enable')
            call('Emulation.setDeviceMetricsOverride', {'width': 800, 'height': 600, 'deviceScaleFactor': 1, 'mobile': False})
            frame = call('Page.getFrameTree')['frameTree']['frame']['id']
            html = '''<style>body{margin:0}#plain{height:150px;background:#eee}a,button,input,[contenteditable]{display:block;margin:20px;width:250px;height:40px}</style>
            <div id=plain></div><a id=link href=#clicked><span>Link</span></a>
            <button id=button onclick="window.buttonClicks=(window.buttonClicks||0)+1"><span>Button</span></button>
            <input id=input><div id=editable contenteditable=true>Edit</div>
            <script>window.bridgeEvents=[];window.__ankiPadTapToken='first';window.webkit={messageHandlers:{reviewTap:{postMessage:body=>bridgeEvents.push(body)}}};</script>'''
            call('Page.setDocumentContent', {'frameId': frame, 'html': html + '<script>' + script + '</script>'})
            click(100, 50); settle()
            assert count() == 1
            assert evaluate('bridgeEvents[0].x') == 0.125
            for element in ['link', 'button', 'input', 'editable']:
                position = evaluate(f"(()=>{{const r=document.getElementById('{element}').getBoundingClientRect();return [r.x+10,r.y+10]}})()")
                click(*position); settle()
                assert count() == 1, element
            assert evaluate('buttonClicks') == 1
            assert evaluate('location.hash') == '#clicked'
            assert evaluate('document.activeElement.id') == 'editable'
            evaluate('document.activeElement.blur()')
            click(100, 50, 1); click(100, 50, 2); click(100, 50, 3); settle()
            assert count() == 1, 'triple click leaked a zone action'
            click(100, 50)
            evaluate("window.__ankiPadTapToken='second'")
            settle(); assert count() == 1, 'old render leaked a zone action'
            evaluate("document.getElementById('plain').textContent='Selectable text'")
            click(300, 80)
            evaluate("(()=>{const range=document.createRange();range.selectNodeContents(document.getElementById('plain'));getSelection().removeAllRanges();getSelection().addRange(range)})()")
            settle(); assert count() == 1, 'selection leaked a zone action'
            evaluate("getSelection().removeAllRanges();document.getElementById('plain').textContent='';document.body.appendChild(Object.assign(document.createElement('div'),{style:'height:2000px'}));scrollTo(0,0)")
            call('Emulation.setTouchEmulationEnabled', {'enabled': True, 'maxTouchPoints': 1})
            def touch(kind, x=100, y=50):
                points = [] if kind == 'touchEnd' else [{'id': 1, 'x': x, 'y': y, 'force': 1, 'radiusX': 2, 'radiusY': 2}]
                call('Input.dispatchTouchEvent', {'type': kind, 'touchPoints': points})
            touch('touchStart'); touch('touchEnd'); settle()
            assert count() == 2, 'trusted touch tap did not reach the plain region'
            touch('touchStart', 400, 500)
            for y in [450, 350, 200, 100]:
                touch('touchMove', 400, y); time.sleep(0.06)
            touch('touchEnd'); settle()
            assert evaluate('scrollY') > 0, 'touch drag did not scroll the fixture'
            assert count() == 2, 'scroll gesture leaked a zone action'
            print(json.dumps({'result': 'PASS', 'browser': call('Browser.getVersion')['product'],
                'checks': ['trusted plain click', 'normalized coordinate', 'nested link/button exclusion',
                           'input/editable focus', 'triple-click cancellation', 'stale-render cancellation', 'selection cancellation', 'trusted touch tap', 'touch scroll exclusion'],
                'limitations': ['Chromium, not iPad WebKit', 'pinch zoom and UIKit fullscreen interactions not covered']}, ensure_ascii=False))
        finally:
            if connection:
                connection.close()
            browser.terminate()
            try:
                browser.wait(timeout=5)
            except subprocess.TimeoutExpired:
                browser.kill(); browser.wait()

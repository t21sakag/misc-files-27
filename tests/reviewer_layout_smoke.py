"""Run the shipped layout script in a real local browser with synthetic media."""
import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile
import time
import socket
import urllib.request
import urllib.error
import contextlib

parser = argparse.ArgumentParser()
parser.add_argument('--browser', required=True)
parser.add_argument('--driver', default='/usr/bin/chromedriver')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
layout_source = (root / 'ios/AnkiPad/AdaptiveReviewLayout.swift').read_text()
script = re.search(r'static let script = #"""\n(.*?)"""#', layout_source, re.S)[1]
image = 'data:image/svg+xml,' + '%3Csvg xmlns="http://www.w3.org/2000/svg" width="1200" height="900"%3E%3Crect width="1200" height="900" fill="orange"/%3E%3C/svg%3E'
cases = {
    'authored': '<div><font id="question" style="font-size:160px!important">calculation</font></div><div><a id="sound" href="ankiplay://q/0" style="font-size:180px!important;text-decoration:underline">▶︎</a></div><p style="font-size:16px">(check the calculation again)</p><hr id="answer"><div><font id="response" size="2">計算</font></div><p style="font-size:16px">（計算をもう一度確認する）</p>',
    'short': '<div id="question" style="font-size:18px">I should have told you earlier.</div><hr id="answer"><div id="response" style="font-size:40px">もっと早く伝えるべきだった。</div>',
    'long': '<div id="question">' + 'English sentences and 日本語の長い説明。 ' * 150 + '</div><hr><div id="response">答え</div>',
    'media': '<div id="question">English 日本語の問題</div><img id="picture"><audio controls></audio><video controls width="240" height="100"></video><hr><div id="response">画像と音声のある答え</div><input id="typeans" value="keep this answer">',
    'annotation': '<div id="question">Mask alignment</div><div id="annotation" style="position:relative;width:600px"><img id="picture" style="width:600px;height:450px"><div id="mask" style="position:absolute;left:60px;top:45px;width:120px;height:90px;background:gray"></div></div><hr><div id="response">マスクと画像</div>',
}
with tempfile.TemporaryDirectory(prefix='review-layout-') as temporary:
    base = Path(temporary)
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    driver = subprocess.Popen([args.driver, '--port=' + str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    endpoint = 'http://127.0.0.1:' + str(port)
    session = ''
    def command(method, path, value=None):
        payload = json.dumps(value).encode() if value is not None else None
        request = urllib.request.Request(endpoint + ('/session/' + session if session else '') + path,
                                         data=payload, headers={'Content-Type': 'application/json'}, method=method)
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)['value']
        if isinstance(result, dict) and result.get('error'):
            raise RuntimeError(result)
        return result
    try:
        deadline = time.monotonic() + 5
        while True:
            try:
                command('GET', '/status')
                break
            except urllib.error.URLError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(.1)
        created = command('POST', '/session', {'capabilities': {'alwaysMatch': {'browserName': 'chrome',
            'goog:chromeOptions': {'binary': args.browser, 'args': ['--headless', '--no-sandbox', '--disable-gpu',
                '--disable-dev-shm-usage', '--disable-background-networking', '--no-first-run', '--window-size=1180,820',
                '--user-data-dir=' + str(base / 'profile')]}}}})
        session = created['sessionId']
        for name, content in cases.items():
            page = base / (name + '.html')
            observer = """
            const qa=document.getElementById('qa');
            let events=0;
            qa.addEventListener('study-layout',()=>events++);
            setTimeout(()=>{
                const image=document.getElementById('picture');
                if(image)image.src=IMAGE_URL;
            },100);
            setTimeout(()=>{
                const q=document.getElementById('question'),a=document.getElementById('response');
                const picture=document.getElementById('picture'),mask=document.getElementById('mask');
                const result={state:qa.dataset.studyLayout,font:Number(qa.dataset.studyFont),height:qa.getBoundingClientRect().height,
                  available:Number(qa.dataset.studyAvailableHeight),question:getComputedStyle(q).fontSize,answer:getComputedStyle(a).fontSize,
                  width:document.documentElement.scrollWidth,viewport:innerWidth,events,sound:document.getElementById('sound')?.getBoundingClientRect().height,
                  input:document.getElementById('typeans')?.value,
                  imageHeight:picture?.getBoundingClientRect().height,
                  maskRatio:mask?mask.getBoundingClientRect().width/picture.getBoundingClientRect().width:null};
                document.getElementById('result').textContent=JSON.stringify(result);
            },1200);
            """.replace('IMAGE_URL', json.dumps(image))
            page.write_text('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">'
                            '<style>body{margin:24px;font-family:sans-serif;text-align:center}img{max-width:100%;height:auto}#result{display:none}</style>'
                            '<body data-reading-scale="1.117647"><div id="qa">' + content + '</div><pre id="result"></pre>'
                            '<script>' + script + '</script><script>' + observer + '</script>')
            command('POST', '/url', {'url': page.as_uri()})
            deadline = time.monotonic() + 8
            result = None
            while time.monotonic() < deadline:
                value = command('POST', '/execute/sync', {'script': "return document.getElementById('result')?.textContent", 'args': []})
                if value:
                    result = json.loads(value)
                    break
                time.sleep(.1)
            assert result is not None, name
            assert result['question'] == result['answer'], (name, result)
            assert result['font'] >= 26.82 and result['events'] < 20, (name, result)
            if name == 'long':
                assert result['state'] == 'scroll' and result['height'] > result['available'], result
            else:
                assert result['state'] == 'fit' and result['height'] <= result['available'] + 1, (name, result)
                assert result['width'] <= result['viewport'] + 1, result
            if name == 'authored':
                assert 44 <= result['sound'] <= 48 and result['font'] <= 1180 / 12 + 1, result
            if name == 'short':
                assert result['font'] > 48, result
            if name == 'media':
                assert result['input'] == 'keep this answer' and result['imageHeight'] <= result['available'] * .55 + 1, result
            if name == 'annotation':
                assert abs(result['maskRatio'] - .2) < .002, result
            print('PASS', name, json.dumps(result, ensure_ascii=False))
    finally:
        if session:
            with contextlib.suppress(Exception):
                command('DELETE', '')
        driver.terminate()
        driver.wait(timeout=10)

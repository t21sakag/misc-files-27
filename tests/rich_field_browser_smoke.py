"""Test actual rich-field HTML/native-injected JS in Chromium, not iPad WebKit."""
import json
from pathlib import Path
import re
import time
from chromium_fixture import chromium

swift = Path('ios/AnkiPad/RichFieldEditor.swift').read_text()
html = re.search(r'view\.loadHTMLString\("""\n([\s\S]*?)\n\s*""", baseURL:', swift)[1]
report = re.search(r'WKUserScript\(source: "(window\.reportField[^\n]+?)", injectionTime:', swift)[1]
command = re.search(r'webView\?\.evaluateJavaScript\("([^\n]+?)", completionHandler: nil\)', swift)[1]
apply = re.search(r'view\.evaluateJavaScript\("([^\n]+?)", completionHandler: nil\)', swift)[1]
with chromium() as browser:
    browser.load(html)
    # CDP evaluation represents trusted native WKUserScript/evaluateJavaScript,
    # which are distinct from scripts/event handlers contained in note HTML.
    browser.evaluate("window.fieldReports=[];window.webkit={messageHandlers:{fieldChanged:{postMessage:value=>fieldReports.push(value)}}}")
    browser.evaluate(report)
    def set_field(value, rtl=False):
        browser.evaluate(apply.replace(r'\(args)', json.dumps([value, 'fixture-field', 'Arial', 28, rtl], ensure_ascii=False)))
    def perform(name, value=''):
        browser.evaluate(command.replace(r'\(args)', json.dumps([name, value], ensure_ascii=False)))
    def select_all():
        browser.evaluate("(()=>{const f=document.getElementById('field');f.focus();const r=document.createRange();r.selectNodeContents(f);const s=getSelection();s.removeAllRanges();s.addRange(r)})()")
    set_field('初期<b>太字</b>', rtl=True)
    assert browser.evaluate("document.getElementById('field').textContent") == '初期太字'
    assert browser.evaluate("document.getElementById('field').dir") == 'rtl'
    assert browser.evaluate("document.getElementById('field').getAttribute('aria-label')") == 'fixture-field'
    assert browser.evaluate("document.getElementById('field').style.fontSize") == '28px'
    browser.evaluate("(()=>{const f=document.getElementById('field');f.focus();getSelection().selectAllChildren(f);getSelection().collapseToEnd()})()")
    browser.call('Input.insertText', {'text': ' 追記🙂 & < >'})
    assert browser.evaluate("document.getElementById('field').textContent") == '初期太字 追記🙂 & < >'
    assert browser.evaluate("fieldReports.at(-1)===document.getElementById('field').innerHTML") is True
    assert '&lt;' in browser.evaluate('fieldReports.at(-1)')
    set_field('選択した単語')
    select_all(); perform('bold')
    assert browser.evaluate("!!document.querySelector('#field b,#field strong')") is True
    bold = browser.evaluate("document.getElementById('field').innerHTML")
    perform('undo')
    assert browser.evaluate("document.getElementById('field').innerHTML") != bold
    perform('redo')
    assert browser.evaluate("document.getElementById('field').innerHTML") == bold
    set_field('リンク'); select_all()
    link = 'https://example.test/path?a=1&b=2'
    perform('createLink', link)
    assert browser.evaluate("document.querySelector('#field a').getAttribute('href')") == link
    assert browser.evaluate('fieldReports.at(-1)') == browser.evaluate("document.getElementById('field').innerHTML")
    set_field('箇条書き'); select_all(); perform('insertUnorderedList')
    assert browser.evaluate("!!document.querySelector('#field ul li')") is True
    set_field("<img src='data:image/png,invalid' onerror='window.noteEventExecuted=true'>保持する文字")
    time.sleep(0.25)
    browser.evaluate("document.querySelector('#field img').dispatchEvent(new Event('error'))")
    assert browser.evaluate("typeof window.noteEventExecuted") == 'undefined'
    assert browser.evaluate("document.getElementById('field').textContent") == '保持する文字'
    print(json.dumps({'result': 'PASS', 'browser': browser.call('Browser.getVersion')['product'],
        'checks': ['actual template/JS extraction', 'font/label/RTL application', 'trusted Unicode insertion and HTML reporting',
                   'bold/undo/redo', 'link value/reporting', 'unordered list', 'note event-handler blocked by CSP'],
        'limitations': ['Chromium, not iPad WebKit', 'Swift bindings/native toolbar focus and actual collection save not exercised']}, ensure_ascii=False))

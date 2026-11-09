"""Exercise authored hierarchy and controls with synthetic, unrelated templates."""
import json
from pathlib import Path
import re
import time

from chromium_fixture import chromium

root = Path(__file__).resolve().parents[1]
source = (root / 'ios/AnkiPad/AdaptiveReviewLayout.swift').read_text()
layout = re.search(r'static let script = #"""\n(.*?)"""#', source, re.S)[1]


def page(prefix, semantic=False):
    control = 'button' if semantic else 'span'
    return '''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
    body { margin:24px; font:20px sans-serif; text-align:center }
    .PREFIX-panel { max-width:520px; margin:auto }
    .PREFIX-badge { display:inline-block; font-size:12px; background:#333; color:white;
        padding:2px 4px; border-radius:3px; cursor:pointer }
    .PREFIX-modes { margin-bottom:12px }
    .PREFIX-choice { display:inline-block; font-size:12px; padding:3px 10px;
        border:1px solid #999; border-radius:10px; cursor:pointer }
    .PREFIX-choice.active { background:green; color:white }
    .PREFIX-heading { font-size:32px; margin:12px 0 }
    .PREFIX-example { font-size:24px; margin:12px 0 }
    .PREFIX-example em { color:green; font-style:normal }
    .PREFIX-panel[data-mode="example"] .PREFIX-heading { display:none }
    .PREFIX-panel[data-mode="heading"] .PREFIX-example { display:none }
    .PREFIX-play { font-size:14px }
    </style><body data-reading-scale="1.117647"><div id="qa">
    <div class="PREFIX-panel" data-mode="both">
      <div class="PREFIX-badge">Label</div>
      <div class="PREFIX-modes"><CONTROL class="PREFIX-choice" data-mode="heading">Heading</CONTROL>
        <CONTROL class="PREFIX-choice" data-mode="example">Example</CONTROL>
        <CONTROL class="PREFIX-choice active" data-mode="both">Both</CONTROL></div>
      <div class="PREFIX-heading">A useful expression</div>
      <div class="PREFIX-example">We will <em>send the final document</em> <a href="#note">tomorrow</a> morning.</div>
      <button class="PREFIX-play">Play example</button>
    </div></div>
    <script>(()=>{
    const panel=document.querySelector('.PREFIX-panel');
    for(const item of panel.querySelectorAll('.PREFIX-choice'))item.addEventListener('click',()=>{
      panel.dataset.mode=item.dataset.mode;
      for(const button of panel.querySelectorAll('.PREFIX-choice'))button.className='PREFIX-choice'+(button===item?' active':'');
    });
    window.fixtureClicks=0;
    panel.querySelector('.PREFIX-play').addEventListener('click',()=>window.fixtureClicks++);
    })();</script><script>LAYOUT</script>'''.replace('PREFIX', prefix).replace('CONTROL', control).replace('LAYOUT', layout)


def metrics(browser, prefix):
    return browser.evaluate('''(()=>{
      const panel=document.querySelector('.PREFIX-panel'),heading=panel.querySelector('.PREFIX-heading'),example=panel.querySelector('.PREFIX-example');
      const choices=Array.from(panel.querySelectorAll('.PREFIX-choice'));
      const font=e=>parseFloat(getComputedStyle(e).fontSize);
      return {heading:font(heading),example:font(example),highlight:font(example.querySelector('em')),
        link:font(example.querySelector('a')),badge:font(panel.querySelector('.PREFIX-badge')),width:panel.getBoundingClientRect().width,viewport:innerWidth,
        overflow:document.documentElement.scrollWidth>innerWidth+1,
        controls:choices.map(e=>({font:font(e),width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height})),
        mode:panel.dataset.mode,headingVisible:heading.getClientRects().length>0,
        state:document.getElementById('qa').dataset.studyLayout};
    })()'''.replace('PREFIX', prefix))


with chromium() as browser:
    browser.call('Emulation.setDeviceMetricsOverride', {'width':1180,'height':650,'deviceScaleFactor':1,'mobile':False})
    for prefix, semantic in [('sample', False), ('unrelated', True)]:
        browser.load(page(prefix, semantic))
        time.sleep(.4)
        initial = metrics(browser, prefix)
        assert .74 <= initial['example'] / initial['heading'] <= .76, initial
        assert initial['highlight'] == initial['example'] == initial['link'], initial
        assert initial['example'] >= 26 and initial['badge'] <= 23, initial
        assert initial['width'] > 700 and not initial['overflow'], initial
        assert all(item['font'] >= 20 and item['width'] >= 44 and item['height'] >= 44 for item in initial['controls']), initial
        browser.evaluate("document.querySelector('." + prefix + "-play').click()")
        assert browser.evaluate('window.fixtureClicks') == 1
        # Use a trusted pointer event on the author-supplied mode control.
        point = browser.evaluate("(()=>{const b=document.querySelector('[data-mode=example]." + prefix + "-choice').getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2}})()")
        for event in ['mousePressed', 'mouseReleased']:
            browser.call('Input.dispatchMouseEvent', {'type':event,'button':'left','clickCount':1,**point})
        time.sleep(.3)
        switched = metrics(browser, prefix)
        assert switched['mode'] == 'example' and not switched['headingVisible'], switched
        browser.evaluate("document.querySelector('." + prefix + "-choice[data-mode=both]').click()")
        time.sleep(.3)
        repeated = metrics(browser, prefix)
        assert abs(repeated['heading'] - initial['heading']) < .1, (initial, repeated)
        assert repeated['controls'] == initial['controls'], (initial, repeated)
        # Template-owned style changes must survive later normalization.
        browser.evaluate("document.querySelector('." + prefix + "-example').style.fontSize='20px'")
        time.sleep(.3)
        changed = metrics(browser, prefix)
        assert .61 <= changed['example'] / changed['heading'] <= .64, changed
        browser.call('Emulation.setDeviceMetricsOverride', {'width':820,'height':1000,'deviceScaleFactor':1,'mobile':False})
        time.sleep(.3)
        portrait = metrics(browser, prefix)
        assert not portrait['overflow'] and portrait['example'] >= 26, portrait
        assert .61 <= portrait['example'] / portrait['heading'] <= .64, portrait
        browser.call('Emulation.setDeviceMetricsOverride', {'width':1180,'height':650,'deviceScaleFactor':1,'mobile':False})
        time.sleep(.3)
        restored = metrics(browser, prefix)
        assert abs(restored['heading'] - changed['heading']) < .1, (changed, restored)
        print('PASS', prefix, json.dumps(initial), 'script/resize', json.dumps(restored))
    browser.load(page('responsive'))
    browser.evaluate("(()=>{const style=document.createElement('style');style.textContent='@media(max-width:900px){.responsive-heading{font-size:30px}.responsive-example{font-size:18px}}';document.head.append(style)})()")
    browser.call('Emulation.setDeviceMetricsOverride', {'width':820,'height':1000,'deviceScaleFactor':1,'mobile':False})
    time.sleep(.3)
    responsive = metrics(browser, 'responsive')
    assert .59 <= responsive['example'] / responsive['heading'] <= .61, responsive
    browser.call('Emulation.setDeviceMetricsOverride', {'width':1180,'height':650,'deviceScaleFactor':1,'mobile':False})
    time.sleep(.3)
    responsive = metrics(browser, 'responsive')
    assert .74 <= responsive['example'] / responsive['heading'] <= .76, responsive
    browser.load('<body data-reading-scale="1.117647"><div id="qa"><div id="zero" style="font-size:0">hidden text<span id="child" style="font-size:24px">Visible text</span></div><div data-study-layout-preserve><button id="preserved" style="font-size:11px">Preserved</button></div></div><script>'+layout+'</script>')
    time.sleep(.3)
    exceptional = browser.evaluate("[getComputedStyle(document.getElementById('zero')).fontSize,parseFloat(getComputedStyle(document.getElementById('child')).fontSize),getComputedStyle(document.getElementById('preserved')).fontSize]")
    assert exceptional[0] == '0px' and exceptional[1] >= 26 and exceptional[2] == '11px', exceptional
print('PASS synthetic templates retain hierarchy, compact badges, actionable controls, script changes and rotation')

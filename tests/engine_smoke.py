"""Exercise the actual Anki engine through the exact C ABI used by the iPad app."""
import ctypes
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import time

lib = ctypes.CDLL(sys.argv[1])
lib.ap_open.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
lib.ap_open.restype = ctypes.c_void_p
lib.ap_call.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lib.ap_call.restype = ctypes.c_void_p
lib.ap_string_free.argtypes = [ctypes.c_void_p]
lib.ap_close.argtypes = [ctypes.c_void_p]


def unpack(ptr):
    assert ptr, 'Null engine response'
    try:
        return json.loads(ctypes.string_at(ptr))
    finally:
        lib.ap_string_free(ptr)


class Engine:
    def __init__(self, root):
        error = ctypes.c_void_p()
        self.handle = lib.ap_open(ctypes.byref(error))
        assert self.handle, unpack(error.value) if error.value else 'No backend'
        root.mkdir(exist_ok=True)
        (root / 'collection.media').mkdir(exist_ok=True)
        self.root = root
        self.call('CollectionService.OpenCollection', {
            'collectionPath': str(root / 'collection.anki2'),
            'mediaFolderPath': str(root / 'collection.media'),
            'mediaDbPath': str(root / 'collection.media.db2'),
        })

    def call(self, method, args=None):
        envelope = unpack(lib.ap_call(self.handle, method.encode(), json.dumps(args or {}).encode()))
        assert 'error' not in envelope, (method, envelope)
        return envelope['ok']

    def close(self):
        self.call('CollectionService.CloseCollection')
        lib.ap_close(self.handle)


def next_card(engine):
    queue = engine.call('SchedulerService.GetQueuedCards', {'fetchLimit': 1})
    assert queue.get('cards'), queue
    card = queue['cards'][0]
    rendered = engine.call('CardRenderingService.RenderExistingCard', {'cardId': card['card']['id']})
    return card, rendered


def main():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        source = Engine(root / 'source')
        types = source.call('NotetypesService.GetNotetypeNames')['entries']
        basic = types[0]['id']
        note = source.call('NotesService.NewNote', {'ntid': basic})
        api_probe = """<div id="droid-api-probe" aria-live="polite"></div><script>
        (async()=>{try {
          const api=AnkiDroidJS.init({developer:'fixture@example.test',version:'0.0.3'});
          const id=await api.ankiGetCardId(), nid=await api.ankiGetCardNid();
          const mark=await api.ankiGetCardMark(), flag=await api.ankiGetCardFlag();
          const tags=await api.ankiGetNoteTags();
          const theme=await api.ankiIsInNightMode();if(!theme.success||theme.value!==matchMedia('(prefers-color-scheme:dark)').matches)throw Error('Native theme mismatch');
          const buildVersion=await AnkiDroidJS.init({developer:'fixture@example.test',version:'0.0.3+fixture.1'}).ankiGetCardId();if(!buildVersion.success||buildVersion.value!==id.value)throw Error('Semantic API build version mismatch');
          const rejected=await AnkiDroidJS.init({developer:'fixture@example.test',version:'0.0.2'}).ankiGetCardId();
          if(!id.success||!(id.value>0)||!nid.success||!(nid.value>0)||!mark.success||typeof mark.value!=='boolean'||!flag.success||!Number.isInteger(flag.value)||flag.value<0||flag.value>7||!tags.success||!Array.isArray(JSON.parse(tags.value))||rejected.success)throw Error('Unexpected API contract');
          if((await api.ankiTtsSetPitch(1)).value!==0||(await api.ankiTtsSetSpeechRate(1)).value!==0||(await api.ankiTtsSetPitch(0)).value!==-1||(await api.ankiTtsStop()).value!==0)throw Error('TTS API status mismatch');
          if((await api.ankiSttSetLanguage('ja-JP')).value!==true||(await api.ankiSttStop()).value!==true)throw Error('Speech recognition configuration mismatch');
          const network=await api.ankiIsActiveNetworkMetered();if(!network.success||typeof network.value!=='boolean')throw Error('Network cost contract mismatch');
          const eta=await api.ankiGetETA();if(!eta.success||!Number.isInteger(eta.value)||eta.value<0)throw Error('ETA contract mismatch');
          if(!['userAction','showHint','showAllHints'].every(name=>typeof globalThis[name]==='function'&&typeof globalThis.ankidroid?.[name]==='function'))throw Error('Template helper globals missing');
          document.getElementById('droid-api-probe').textContent='AnkiDroid API metadata verified';
        }catch(error){document.getElementById('droid-api-probe').textContent='AnkiDroid API error: '+error;}})();
        </script><button id="preview-api-check">Preview API check</button><div id="preview-api-status" aria-live="polite"></div><script>
        document.getElementById('preview-api-check').onclick=async()=>{
          const out=document.getElementById('preview-api-status');
          const api=AnkiDroidJS.init({developer:'fixture@example.test',version:'0.0.3'});
          const names=['none','red','orange','green','blue','pink','turquoise','purple'];
          let original;
          try {
            const id=await api.ankiGetCardId(), flag=await api.ankiGetCardFlag();
            if(!id.success||id.value<=0||!flag.success)throw Error('Metadata unavailable');
            original=flag.value;
            const desired=original===1?4:1;
            const changed=await api.ankiToggleFlag(names[desired]);
            if(!changed.success||changed.value!==true||(await api.ankiGetCardFlag()).value!==desired)throw Error('Flag write mismatch');
            const restored=await api.ankiToggleFlag(names[original]);
            if(!restored.success||(await api.ankiGetCardFlag()).value!==original)throw Error('Flag restore mismatch');
            original=undefined;
            out.textContent='Preview API verified';
          }catch(error){out.textContent='Preview API error: '+error;}
          finally{if(original!==undefined&&(await api.ankiGetCardFlag()).value!==original)await api.ankiToggleFlag(names[original]);}
        };
        </script><button id="api-mutations">API mutations</button><div id="api-mutations-status" aria-live="polite"></div><button id="collection-query">API collection query</button><div id="collection-query-status" aria-live="polite"></div><button id="api-navigation">API navigation</button><button id="api-options">API options</button><script>
        (()=>{const api=AnkiDroidJS.init({developer:'fixture@example.test',version:'0.0.3'});let callbackCount=0;
          addHook('ankiSearchCard',result=>{
            callbackCount++;const valid=Array.isArray(result)&&result.length>0&&result.every(item=>item.cardId>0&&item.noteId>0&&typeof item.fieldsData==='object');
            document.getElementById('collection-query-status').textContent=!valid?'Collection query payload mismatch':callbackCount===2?'Collection query verified':'Collection callbacks: '+callbackCount;
          });
          document.getElementById('api-mutations').onclick=async()=>{
            document.getElementById('api-mutations-status').textContent='API mutation started';
            let oldFlag,oldMark;
            try { oldFlag=(await api.ankiGetCardFlag()).value; oldMark=(await api.ankiGetCardMark()).value; }
            catch(error){document.getElementById('api-mutations-status').textContent='API mutation read error: '+error;return;}
            const names=['none','red','orange','green','blue','pink','turquoise','purple'];let failure=null;
            try {
              const target=oldFlag===1?4:1;
              if(!(await api.ankiToggleFlag(names[target])).value||(await api.ankiGetCardFlag()).value!==target)throw Error('Flag write failed');
              if(!(await api.ankiMarkCard()).value||(await api.ankiGetCardMark()).value===oldMark)throw Error('Mark write failed');
            }catch(error){failure=String(error);}
            try {
              if((await api.ankiGetCardFlag()).value!==oldFlag)await api.ankiToggleFlag(names[oldFlag]);
              if((await api.ankiGetCardMark()).value!==oldMark)await api.ankiMarkCard();
              if((await api.ankiGetCardFlag()).value!==oldFlag||(await api.ankiGetCardMark()).value!==oldMark)throw Error('API state restoration failed');
            }catch(error){failure=String(error);}
            document.getElementById('api-mutations-status').textContent=failure?'API mutation error: '+failure:'AnkiDroid API mutations verified';
          };
          document.getElementById('api-navigation').onclick=()=>api.ankiShowNavigationDrawer();
          document.getElementById('api-options').onclick=()=>api.ankiShowOptionsMenu();
          document.getElementById('collection-query').onclick=async()=>{
            callbackCount=0;const results=await Promise.all([api.ankiSearchCardWithCallback(''),api.ankiSearchCardWithCallback('')]);
            if(results.some(result=>!result.value))document.getElementById('collection-query-status').textContent='Collection access denied';
          };
        })();
        </script><button id="api-dialogs">API dialogs</button><div id="api-dialogs-status" aria-live="polite"></div><script>
        document.getElementById('api-dialogs').onclick=()=>{
          const input=prompt('Template prompt','');
          if(input===null){if(!confirm('Template cancel confirm'))document.getElementById('api-dialogs-status').textContent='Template dialog cancellation verified';return;}
          if(input==='template input'&&confirm('Template confirm')){
            alert('Template alert');document.getElementById('api-dialogs-status').textContent='Template dialogs verified';
          }
        };
        </script><div id="template-action-status" aria-live="polite"></div><a class="hint" href="#" onclick="this.style.display='none';document.getElementById('template-hint-status').textContent='Template hint revealed';return false;">ヒント</a><div id="template-hint-status" aria-live="polite"></div><script>globalThis.userJs9=()=>{document.getElementById('template-action-status').textContent='Template action 9 verified';};</script><iframe id="embedded-fixture" title="Embedded card content"></iframe><div id="embedded-status" aria-live="polite"></div><script>
        (()=>{const frame=document.getElementById('embedded-fixture');
          window.addEventListener('message',event=>{if(event.source===frame.contentWindow&&event.data==='native-denied')document.getElementById('embedded-status').textContent='Embedded frame loaded; native bridge denied';});
          const child="<p>Embedded card content loaded</p><script>"+
            "(async()=>{try{await window.webkit.messageHandlers.droidAPI.postMessage({endpoint:'toggleFlag',request:{developer:'fixture@example.test',version:'0.0.3',data:'red'}});parent.postMessage('native-unexpected','*');}catch(error){parent.postMessage(String(error).includes('unavailable in this view')?'native-denied':'native-unexpected-error','*');}})();"+
            "<"+"/script>";
          frame.src='data:text/html;charset=utf-8,'+encodeURIComponent(child);
        })();
        </script>"""
        note['fields'] = ['iPad移植の質問' + api_probe, 'Rustエンジンの解答 [sound:test.wav] <img src="test.svg">']
        added = source.call('NotesService.AddNote', {'note': note, 'deckId': '1'})
        assert added.get('noteId')
        (source.root / 'collection.media' / 'test.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        # Small valid silent PCM WAV used to verify media round-tripping.
        import wave
        with wave.open(str(source.root / 'collection.media' / 'test.wav'), 'wb') as audio:
            audio.setparams((1, 2, 8000, 80, 'NONE', 'not compressed'))
            audio.writeframes(b'\0' * 160)
        auto_config = source.call('DeckConfigService.GetDeckConfig', {'dcid': '1'})
        auto_config['config'].update({'secondsToShowQuestion': 8, 'secondsToShowAnswer': 8, 'answerAction': 'ANSWER_ACTION_ANSWER_GOOD', 'waitForAudio': False})
        source.call('DeckConfigService.UpdateDeckConfigs', {'targetDeckId': '1', 'configs': [auto_config]})
        package = root / 'fixture.apkg'
        source.call('ImportExportService.ExportAnkiPackage', {
            'outPath': str(package), 'options': {'withScheduling': True, 'withDeckConfigs': True, 'withMedia': True},
            'limit': {'wholeCollection': {}},
        })
        assert package.stat().st_size > 0
        if len(sys.argv) > 2:
            import shutil
            output = Path(sys.argv[2])
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(package, output)
        source.close()
        engine = Engine(root / 'destination')
        options = engine.call('ImportExportService.GetImportAnkiPackagePresets')
        imported = engine.call('ImportExportService.ImportAnkiPackage', {'packagePath': str(package), 'options': options})
        print('Import:', imported)
        assert (engine.root / 'collection.media' / 'test.wav').exists()
        assert (engine.root / 'collection.media' / 'test.svg').exists()
        decks = engine.call('DecksService.DeckTree', {'now': str(int(time.time()))})
        assert decks.get('children'), decks
        engine.call('DecksService.SetCurrentDeck', {'did': '1'})
        card, rendered = next_card(engine)
        assert 'iPad移植の質問' in json.dumps(rendered, ensure_ascii=False), rendered
        assert 'Rustエンジンの解答' in json.dumps(rendered, ensure_ascii=False), rendered
        av = engine.call('CardRenderingService.ExtractAvTags', {'text': '音声 [sound:test.wav]', 'questionSide': True})
        assert av['avTags'][0]['soundOrVideo'] == 'test.wav', av
        states = card['states']
        intervals = engine.call('SchedulerService.DescribeNextStates', states)
        assert len(intervals['vals']) == 4, intervals
        engine.call('SchedulerService.AnswerCard', {
            'cardId': card['card']['id'], 'currentState': states['current'], 'newState': states['good'],
            'rating': 2, 'answeredAtMillis': str(int(time.time() * 1000)), 'millisecondsTaken': 2000,
        })
        engine.call('CollectionService.Undo')
        undone, _ = next_card(engine)
        assert undone['card']['id'] == card['card']['id']
        assert undone['states']['current'] == states['current']
        # Re-answer after undo, then verify durable review history using SQLite after closing.
        engine.call('SchedulerService.AnswerCard', {
            'cardId': undone['card']['id'], 'currentState': undone['states']['current'], 'newState': undone['states']['easy'],
            'rating': 3, 'answeredAtMillis': str(int(time.time() * 1000)), 'millisecondsTaken': 1500,
        })
        engine.close()
        with sqlite3.connect(engine.root / 'collection.anki2') as db:
            assert db.execute('select count(*) from revlog').fetchone()[0] == 1
            assert db.execute('select ease from revlog').fetchone()[0] == 4
        reopened = Engine(engine.root)
        saved = reopened.call('CardsService.GetCard', {'cid': card['card']['id']})
        assert saved['reps'] == 1, saved
        assert saved['id'] == card['card']['id'], saved
        reopened.close()
        # Bad input returns a structured error, never a C ABI crash.
        invalid = unpack(lib.ap_call(None, b'DecksService.DeckTree', b'{}'))
        assert 'error' in invalid
        error = ctypes.c_void_p()
        handle = lib.ap_open(ctypes.byref(error))
        assert handle
        invalid = unpack(lib.ap_call(handle, b'UnknownService.Missing', b'{}'))
        assert 'error' in invalid
        invalid = unpack(lib.ap_call(handle, b'DecksService.DeckTree', b'{invalid'))
        assert 'error' in invalid
        lib.ap_close(handle)
    print('PASS: real .apkg import/export + media + render + schedule + undo + persistence + C ABI errors')

if __name__ == "__main__":
    main()

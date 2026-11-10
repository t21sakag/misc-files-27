"""Production Swift deck-create adapter -> actual native C ABI, no model IDs."""
from engine_smoke import Engine, lib, unpack
from pathlib import Path
import ctypes, json, subprocess, sys, tempfile

with tempfile.TemporaryDirectory() as directory:
    engine = Engine(Path(directory)/'collection')
    child = subprocess.Popen([sys.argv[2]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def operate(name, parent=None, lookup_failure=False):
        selected_before = engine.call('DecksService.GetCurrentDeck')['id']
        child.stdin.write(json.dumps({'name': name, 'parent': parent})+'\n'); child.stdin.flush()
        calls=[]
        while True:
            line=child.stdout.readline(); assert line, 'Swift deck adapter exited'
            value=json.loads(line)
            if 'done' in value:
                assert engine.call('DecksService.GetCurrentDeck')['id']==selected_before, (name, calls)
                return value,calls
            method=value['method']; calls.append(method)
            if lookup_failure and method=='DecksService.GetDeckIdByName':
                reply={'error':'Injected storage error','kind':2}
            else:
                result=unpack(lib.ap_call(engine.handle, method.encode(), json.dumps(value['args']).encode()))
                reply={'ok':result['ok']} if 'ok' in result else {'error':result['error'],'kind':result.get('errorKind')}
            child.stdin.write(json.dumps(reply)+'\n'); child.stdin.flush()
    def names():
        return engine.call('DecksService.GetDeckNames', {'includeFiltered':True})['entries']
    try:
        created,calls=operate('Parent::Existing'); assert created['done'],created
        parent=engine.call('DecksService.GetDeckIdByName', {'val':'Parent'})['did']
        assert engine.call('DecksService.GetDeck',{'did':created['id']})['name']=='Parent::Existing'
        baseline=names()
        for duplicate in ['Parent::Existing','parent::existing',' Parent :: Existing ']:
            result,calls=operate(duplicate); assert not result['done'],result
            assert calls==['DecksService.GetDeckIdByName'] and names()==baseline
        engine.call('DecksService.RenameDeck',{'deckId':parent,'newName':'Renamed'})
        result,calls=operate('Child',parent)
        assert result['done'] and engine.call('DecksService.GetDeck',{'did':result['id']})['name']=='Renamed::Child'
        baseline=names()
        result,calls=operate('No write',lookup_failure=True)
        assert not result['done'] and calls==['DecksService.GetDeckIdByName'] and names()==baseline
        result,calls=operate('   '); assert not result['done'] and calls==[] and names()==baseline
        result,calls=operate('Missing parent','9223372036854775807')
        assert not result['done'] and calls==['DecksService.GetDeck'] and names()==baseline
        result,calls=operate('""',parent)
        assert not result['done'] and calls==[] and names()==baseline
        filtered=engine.call('DecksService.GetOrCreateFilteredDeck',{'did':'0'}); filtered['name']='Filtered'; filtered['allowEmpty']=True
        fid=engine.call('DecksService.AddOrUpdateFilteredDeck',filtered)['id']; baseline=names()
        result,calls=operate('Not allowed',fid)
        assert not result['done'] and calls==['DecksService.GetDeck'] and names()==baseline
        assert not engine.call('SearchService.SearchCards',{'search':''}).get('ids')
        child.stdin.close(); assert child.wait(timeout=10)==0
    finally:
        if child.poll() is None: child.kill(); child.wait()
        engine.close()
print('PASS: actual deck IDs, duplicate/native-normalized-name rejection without writes, stable parent ID after rename, lookup failure/empty/missing/filtered guards, no current deck or note mutation')

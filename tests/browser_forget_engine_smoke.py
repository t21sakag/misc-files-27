"""Production Swift reset adapter -> actual C ABI, including backup and undo."""
from pathlib import Path
import itertools,json,sqlite3,subprocess,sys,tempfile
from engine_smoke import Engine

with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary)/'reset';engine=Engine(root)
    tid=engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    nids=[];cids=[]
    for index in range(2):
        note=engine.call('NotesService.NewNote',{'ntid':tid});note['fields']=['Reset'+str(index),'unchanged']
        engine.call('NotesService.AddNote',{'note':note,'deckId':'1'})
        nid=engine.call('SearchService.SearchNotes',{'search':'Reset'+str(index)})['ids'][0];nids.append(nid)
        cid=engine.call('SearchService.SearchCards',{'search':'nid:'+nid})['ids'][0];cids.append(cid)
        card=engine.call('CardsService.GetCard',{'cid':cid})
        card.update(ctype=2,queue=2,due=1,interval=30,easeFactor=2500,reps=8,lapses=3,originalPosition=17+index,flags=2)
        engine.call('CardsService.UpdateCards',{'cards':[card]})
    before=[engine.call('CardsService.GetCard',{'cid':cid}) for cid in cids]
    notes=[engine.call('NotesService.GetNote',{'nid':nid}) for nid in nids]
    child=subprocess.Popen([sys.argv[2]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    def operate(ids,restore=False,counts=False,fail_backup=False):
        child.stdin.write(json.dumps({'ids':ids,'restore':restore,'counts':counts})+'\n');child.stdin.flush();calls=[]
        while True:
            line=child.stdout.readline();assert line,'Swift adapter exited'
            message=json.loads(line)
            if 'done' in message:return message['done'],calls
            method=message['method'];args=message['args'];calls.append(method)
            try:
                if method=='_backup':
                    if fail_backup:raise RuntimeError('Injected backup failure')
                    folder=root/'backups';folder.mkdir(exist_ok=True)
                    response=engine.call('CollectionService.CreateBackup',{'backupFolder':str(folder),'force':True,'waitForCompletion':True})
                else:response=engine.call(method,args)
                reply={'ok':response}
            except (AssertionError,RuntimeError):reply={'error':True}
            child.stdin.write(json.dumps(reply)+'\n');child.stdin.flush()
    try:
        for restore,counts in itertools.product([False,True],repeat=2):
            success,calls=operate([cids[0]],restore,counts);assert success,calls
            assert calls==['CardsService.GetCard','_backup','SchedulerService.ScheduleCardsAsNew']
            current=engine.call('CardsService.GetCard',{'cid':cids[0]})
            assert current.get('ctype',0)==0 and current.get('queue',0)==0
            assert current.get('reps',0)==(0 if counts else 8) and current.get('lapses',0)==(0 if counts else 3)
            assert (current['due']==17) is restore,(restore,current)
            assert current['flags']==before[0]['flags'] and current['noteId']==nids[0]
            assert engine.call('CardsService.GetCard',{'cid':cids[1]})==before[1]
            assert list((root/'backups').glob('*.colpkg')),'Backup must exist before mutation'
            engine.call('CollectionService.Undo')
            assert [engine.call('CardsService.GetCard',{'cid':cid}) for cid in cids]==before
        success,calls=operate([cids[0],'9223372036854775807']);assert not success
        assert calls==['CardsService.GetCard','CardsService.GetCard'],'Missing target must abort before backup or partial scheduling'
        success,calls=operate([cids[0]],fail_backup=True);assert not success and 'SchedulerService.ScheduleCardsAsNew' not in calls
        success,calls=operate([]);assert not success and calls==[]
        assert [engine.call('CardsService.GetCard',{'cid':cid}) for cid in cids]==before
        assert [engine.call('NotesService.GetNote',{'nid':nid}) for nid in nids]==notes
        child.stdin.close();assert child.wait(timeout=10)==0
    finally:
        if child.poll() is None:child.kill();child.wait()
        engine.close()
print('PASS: production Swift + CABI reset options4, selected scope/counters/position, actual backup, undo, stale target and failed backup abort, unchanged notes/unselected card')

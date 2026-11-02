"""Actual Swift structured request -> actual backend -> matching persisted notes."""
from pathlib import Path
import copy,json,subprocess,sys,tempfile
from engine_smoke import Engine

with tempfile.TemporaryDirectory() as directory:
    engine=Engine(Path(directory)/'structured')
    type1=engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema=engine.call('NotetypesService.GetNotetype',{'ntid':type1})
    second=copy.deepcopy(schema);second['id']='0';second['name']='Structured second type'
    type2=engine.call('NotetypesService.AddNotetype',second)['id']
    deck=engine.call('DecksService.NewDeck');deck['name']='Structured old deck'
    engine.call('DecksService.AddDeck',deck)
    deck2=next(d['id'] for d in engine.call('DecksService.GetDeckNames')['entries'] if d['name']=='Structured old deck')
    nids=[];cids=[]
    for index in range(4):
        note=engine.call('NotesService.NewNote',{'ntid':type2 if index==3 else type1})
        note['fields']=['Structured'+str(index),'unchanged'];note['tags']=['alpha' if index%2==0 else 'beta']
        engine.call('NotesService.AddNote',{'note':note,'deckId':deck2 if index>=2 else '1'})
        found=engine.call('SearchService.SearchNotes',{'search':'Structured'+str(index)})['ids']
        assert len(found)==1
        nid=found[0]
        cid=engine.call('SearchService.SearchCards',{'search':'nid:'+nid})['ids'][0]
        engine.call('CardsService.SetFlag',{'cardIds':[cid],'flag':[1,2,0,1][index]})
        nids.append(nid);cids.append(cid)
    engine.call('SchedulerService.BuryOrSuspendCards',{'cardIds':[cids[1]],'mode':'SUSPEND'})
    engine.call('SchedulerService.BuryOrSuspendCards',{'cardIds':[cids[2]],'mode':'BURY_USER'})
    child=subprocess.Popen([sys.argv[2]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    checks=0
    def check(request, expected, decks=None, types=None, field=None):
        global checks
        if decks is None:decks={d['id']:d['name'] for d in engine.call('DecksService.GetDeckNames')['entries']}
        if types is None:types={d['id']:d['name'] for d in engine.call('NotetypesService.GetNotetypeNames')['entries']}
        child.stdin.write(json.dumps({'request':request,'decks':decks,'types':types,'field':field})+'\n');child.stdin.flush()
        while True:
            line=child.stdout.readline();assert line,'Swift driver stopped'
            message=json.loads(line)
            if 'node' not in message:break
            response=engine.call('SearchService.BuildSearchString',message['node'])
            child.stdin.write(json.dumps(response)+'\n');child.stdin.flush()
        if expected is None:assert message.get('error') is True,(request,message)
        else:
            actual=engine.call('SearchService.SearchNotes',{'search':message['query']}).get('ids',[])
            assert set(actual)=={nids[i] for i in expected},(request,message,actual,expected)
            if field is None:assert message['encoded']['q']==request['q']
            elif field.get('combine',True):assert message['encoded']['did']==request.get('did',[])
        checks+=1
        return message
    try:
        before=[engine.call('NotesService.GetNote',{'nid':nid}) for nid in nids]
        check({'q':''},[0,1,2,3])
        check({'q':'Structured0'},[0])
        filtered=check({'q':' ','did':[deck2]},[2,3]);assert not filtered['empty']
        check({'q':'','did':['1',deck2]},[0,1,2,3])
        check({'q':'','did':['1'],'t':['alpha','beta']},[0,1])
        check({'q':'','did':[deck2],'t':['alpha']},[2])
        check({'q':'','f':[1]},[0,3])
        check({'q':'','f':[1,2]},[0,1,3])
        check({'q':'','f':[0]},[2])
        check({'q':'','ntid':[type2]},[3])
        check({'q':'','ntid':[type1,type2]},[0,1,2,3])
        check({'q':'','s':[3]},[2])
        check({'q':'','s':[4]},[1])
        check({'q':'','s':[3,4]},[1,2])
        check({'q':'Structured','did':[deck2],'f':[1],'t':['beta'],'ntid':[type2],'s':[0]},[3])
        check({'q':'Structured0','did':[deck2]},[])
        check({'q':'','did':['999999']},None)
        check({'q':'','did':['01']},None)
        check({'q':'','ntid':[type2]},None,types={})
        check({'q':'','f':[8]},None)
        check({'q':'','s':[5]},None)
        check({'did':[deck2]},None)
        back=schema['fields'][1]['name']
        check({'q':'Structured','did':[deck2]},[2,3],field={'name':back,'mode':'contains','text':'unchanged'})
        check({'q':'Structured0','did':[deck2]},[0,1,2,3],field={'name':back,'mode':'exact','text':'unchanged','combine':False})
        assert before==[engine.call('NotesService.GetNote',{'nid':nid}) for nid in nids]
        engine.call('DecksService.RenameDeck',{'deckId':deck2,'newName':'Structured renamed deck'})
        value=engine.call('NotetypesService.GetNotetype',{'ntid':type2});value['name']='Structured renamed type'
        engine.call('NotetypesService.UpdateNotetype',value)
        check({'q':'','did':[deck2],'ntid':[type2]},[3])
        check({'q':'','did':[deck2],'ntid':[type2]},[3],field={'name':back,'mode':'exact','text':'unchanged'})
        assert engine.call('SearchService.SearchNotes',{'search':'deck:"Structured old deck"'}).get('ids',[])==[]
        child.stdin.close();assert child.wait(timeout=10)==0
    finally:
        if child.poll() is None:child.kill();child.wait()
        engine.close()
print(f'PASS: {checks} actual Swift/CABI structured searches: OR/AND, stable deck/type rename, flag/state storage-code mapping, empty query with filters, missing references rejected and no note writes')

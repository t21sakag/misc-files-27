"""Run the actual Swift builder against the real C ABI search engine."""
from pathlib import Path
import json,subprocess,sys,tempfile
from engine_smoke import Engine

with tempfile.TemporaryDirectory() as temporary:
    engine=Engine(Path(temporary)/'fields')
    tid=engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema=engine.call('NotetypesService.GetNotetype',{'ntid':tid})
    front,back=[field['name'] for field in schema['fields'][:2]]
    note_ids=[]
    for index,text in enumerate(['cat','concatenate','literal*star','','日本語']):
        note=engine.call('NotesService.NewNote',{'ntid':tid})
        note['fields']=['row'+str(index),text]
        engine.call('NotesService.AddNote',{'note':note,'deckId':'1'})
        note_ids.append(engine.call('SearchService.SearchNotes',{'search':front+':row'+str(index)})['ids'][0])
    before={nid:engine.call('NotesService.GetNote',{'nid':nid}) for nid in note_ids}
    child=subprocess.Popen([sys.argv[2]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    try:
        cases=[('contains','cat',[0,1]),('exact','cat',[0]),('empty','',[3]),
               ('nonEmpty','',[0,1,2,4]),('exists','',list(range(5))),
               ('contains','*',[2]),('exact','literal*star',[2]),('contains','日本',[4])]
        requests=[({'field':back,'mode':mode,'text':text},expected) for mode,text,expected in cases]
        requests += [({'field':back,'mode':'exact','text':'cat','current':front+':row0','combine':True},[0]),
                     ({'field':back,'mode':'exact','text':'cat','current':front+':row1','combine':True},[]),
                     ({'field':'A " field','mode':'contains','text':'a*b'},[]),
                     ({'field':'','mode':'exists'},None)]
        for request,expected in requests:
            child.stdin.write(json.dumps(request)+'\n');child.stdin.flush()
            while True:
                line=child.stdout.readline();assert line,'Swift builder exited before reply'
                message=json.loads(line)
                if 'node' in message:
                    response=engine.call('SearchService.BuildSearchString',message['node'])
                    child.stdin.write(json.dumps(response)+'\n');child.stdin.flush()
                else:break
            if expected is None:assert message.get('error') is True
            else:
                actual=engine.call('SearchService.SearchNotes',{'search':message['query']}).get('ids',[])
                assert set(actual)=={note_ids[i] for i in expected},(request,message,actual,expected)
        after={nid:engine.call('NotesService.GetNote',{'nid':nid}) for nid in note_ids}
        assert before==after,'Search construction must not mutate notes'
        child.stdin.close();assert child.wait(timeout=10)==0
    finally:
        if child.poll() is None:child.kill();child.wait()
        engine.close()
print('PASS: actual Swift field builder + native engine: contains/exact/empty/nonempty/exists, literal star, Unicode, quoted field, AND isolation, invalid field and no mutations')

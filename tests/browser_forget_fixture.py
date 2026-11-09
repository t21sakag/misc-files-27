"""Export and actually reimport a reviewed two-template reset fixture."""
from pathlib import Path
import copy,json,sys,tempfile
from engine_smoke import Engine

with tempfile.TemporaryDirectory() as directory:
    engine=Engine(Path(directory)/'reset-fixture')
    tid=engine.call('NotetypesService.GetNotetypeNames')['entries'][0]['id']
    schema=engine.call('NotetypesService.GetNotetype',{'ntid':tid})
    schema['id']='0';schema['name']='Reset paired fixture';schema['templates'][0]['name']='Reset Forward'
    sibling=copy.deepcopy(schema['templates'][0]);sibling.pop('ord',None);sibling['name']='Reset Reverse'
    sibling['config']['qFormat']='Sibling: '+sibling['config']['qFormat'];schema['templates'].append(sibling)
    tid=engine.call('NotetypesService.AddNotetype',schema)['id']
    for index in range(3):
        note=engine.call('NotesService.NewNote',{'ntid':tid});note['fields']=['row'+str(index),'Reset answer']
        engine.call('NotesService.AddNote',{'note':note,'deckId':'1'})
    cids=engine.call('SearchService.SearchCards',{'search':''})['ids'];assert len(cids)==6
    cards=[]
    for index,cid in enumerate(cids):
        card=engine.call('CardsService.GetCard',{'cid':cid})
        card.update(ctype=2,queue=2,due=1,interval=30,easeFactor=2500,reps=8,lapses=3,originalPosition=17+index)
        cards.append(card)
    engine.call('CardsService.UpdateCards',{'cards':cards})
    out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True);package=out/'browser-forget.apkg'
    engine.call('ImportExportService.ExportAnkiPackage',{'outPath':str(package),
        'options':{'withMedia':False,'withScheduling':True},'limit':{'wholeCollection':{}}})
    imported=Engine(Path(directory)/'reimported')
    presets=imported.call('ImportExportService.GetImportAnkiPackagePresets')
    # Match production Engine.importPackage: native confirmation preserves scheduling/configs.
    presets.update(withScheduling=True,withDeckConfigs=True)
    imported.call('ImportExportService.ImportAnkiPackage',{'packagePath':str(package),'options':presets})
    reviewed=imported.call('SearchService.SearchCards',{'search':'is:review'})['ids'];assert len(reviewed)==6
    assert not imported.call('SearchService.SearchCards',{'search':'is:new'}).get('ids',[])
    for cid in reviewed:
        card=imported.call('CardsService.GetCard',{'cid':cid});assert card['reps']==8 and card['lapses']==3
        assert card.get('originalPosition',0)>=17
    query='row0 card:"Reset Forward"'
    assert len(imported.call('SearchService.SearchCards',{'search':query})['ids'])==1
    assert len(imported.call('SearchService.SearchCards',{'search':'row0'})['ids'])==2
    for cid in reviewed:imported.call('CardRenderingService.RenderExistingCard',{'cardId':cid,'partialRender':True})
    (out/'browser-forget.json').write_text(json.dumps({'notes':3,'cards':6,'reviewed':6,'reps':8,'lapses':3,
        'singleQuery':query,'fronts':['row0','row1','row2']})+'\n')
    imported.close();engine.close()
print('PASS: reset fixture actually reimports as 3 notes/6 reviewed cards, nonzero counters, original positions and exact one-card/two-sibling queries')

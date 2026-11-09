"""Check early fixture readiness/rejection without an Apple SDK or network."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import zipfile

root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    base=Path(directory);(base/'build').mkdir();tools=base/'tools';tools.mkdir()
    fake=tools/'xcrun';fake.write_text('#!/bin/sh\nexit 0\n');fake.chmod(0o755)
    environment=dict(os.environ,PATH=str(tools)+os.pathsep+os.environ['PATH'])
    selected=base/'selected.txt';report=base/'build/ui-prerequisites.json';image=base/'build/occlusion-fixture.png'
    selected.write_text('-only-testing:AnkiPadUITests/ShareExtensionFlowTests/testPhotoShareSurvivesConfirmationCancelAndRelaunchBeforeSavingMedia\n')
    command=[sys.executable,str(root/'scripts/ui-prerequisites.py'),'--simulator','fixture','--selections',str(selected)]
    def check(success):
        result=subprocess.run(command,cwd=base,env=environment,text=True,capture_output=True)
        assert (result.returncode==0)==success,(result.stdout,result.stderr)
        return json.loads(report.read_text())
    missing=check(False);assert missing['photo_required'] and not missing['fixture_valid']
    subprocess.run([sys.executable,str(root/'tests/make_occlusion_image.py'),str(image)],check=True)
    ready=check(True);assert ready=={'photo_required':True,'fixture_valid':True,'photo_host_installed':True,'preview_package_required':False}
    data=bytearray(image.read_bytes());data[-5]^=1;image.write_bytes(data)
    corrupt=check(False);assert not corrupt['fixture_valid']
    selected.write_text('-only-testing:AnkiPadUITests/ShareExtensionFlowTests/testSafariSharePersistsUntilExplicitNoteSaveAndDoesNotReopenAfterCancel\n')
    not_required=check(True);assert not not_required['photo_required']
    selected.write_text('-only-testing:AnkiPadUITests/BrowserToolsFlowTests/testNotesPreviewUsesRepresentativesUntilMultipleRowsSelected\n')
    missing_preview=check(False);assert missing_preview['preview_package_required'] and not missing_preview['preview_package_valid']
    package=base/'ios/AnkiPadUITests/ReceivedFixtures/preview.apkg';package.parent.mkdir(parents=True)
    with zipfile.ZipFile(package,'w') as archive:archive.writestr('collection.anki21b',b'synthetic container check; actual engine validates generated fixture separately')
    assert check(True)['preview_package_valid']
    selected.write_text('-only-testing:AnkiPadUITests/BrowserToolsFlowTests/testBrowserSelectionOrderSurvivesDeselectionAndReselection\n')
    assert check(True)['preview_package_valid']
    package.write_bytes(b'broken package');assert not check(False)['preview_package_valid']
    selected.write_text('-only-testing:AnkiPadUITests/BrowserFieldSearchFlowTests/testNamedFieldTextSearchCancelExactAndLiteralStar\n')
    missing_field=check(False);assert missing_field['field_package_required'] and not missing_field['field_package_valid']
    field_package=package.with_name('field-search.apkg')
    with zipfile.ZipFile(field_package,'w') as archive:archive.writestr('collection.anki21b',b'container only; real engine separately proves exported/reimported notes')
    no_manifest=check(False);assert no_manifest['field_package_valid'] and not no_manifest['field_manifest_valid']
    field_manifest=field_package.with_suffix('.json')
    field_manifest.write_text(json.dumps({'front':'Front','back':None,'rows':5}))
    assert not check(False)['field_manifest_valid']
    field_manifest.write_text(json.dumps({'front':'Front','back':'Back','rows':5}))
    assert check(True)['field_manifest_valid']
    selected.write_text('-only-testing:AnkiPadUITests/BrowserSearchFiltersFlowTests/testStructuredFilterORCancelFieldIntersectionAndClear\n')
    assert check(True)['field_manifest_valid']
    selected.write_text('-only-testing:AnkiPadUITests/BrowserFieldSearchFlowTests/testNamedFieldEmptyNonemptyExistsAndCurrentQueryIntersection\n')
    assert check(True)['field_manifest_valid']
    field_package.write_bytes(b'corrupt')
    assert not check(False)['field_package_valid']
    selected.write_text('-only-testing:AnkiPadUITests/BrowserForgetFlowTests/testCardResetCancelOptionsPersistAndUndoLeavesSiblingReviewed\n')
    assert not check(False)['reset_package_valid']
    reset_package=base/'ios/AnkiPadUITests/ReceivedFixtures/browser-forget.apkg'
    with zipfile.ZipFile(reset_package,'w') as archive:
        archive.writestr('collection.anki21b',b'container readiness only')
    reset_manifest=reset_package.with_suffix('.json')
    reset_manifest.write_text(json.dumps({'notes':3,'cards':6,'reviewed':0,'reps':8,'lapses':3,'singleQuery':'row0 card:"Reset Forward"'}))
    assert not check(False)['reset_manifest_valid']
    reset_manifest.write_text(json.dumps({'notes':3,'cards':6,'reviewed':6,'reps':8,'lapses':3,'singleQuery':'row0 card:"Reset Forward"'}))
    assert check(True)['reset_manifest_valid']
    selected.write_text('-only-testing:AnkiPadUITests/Missing/testUnknown\n');check(False)
print('PASS: photo preflight rejects missing/corrupt pixels and unknown cases, records failures, checks preview packages before build/UI, and skips unrelated fixture dependencies')

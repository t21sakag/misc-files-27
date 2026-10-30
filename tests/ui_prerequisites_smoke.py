"""Check early fixture readiness/rejection without an Apple SDK or network."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

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
    ready=check(True);assert ready=={'photo_required':True,'fixture_valid':True,'photo_host_installed':True}
    data=bytearray(image.read_bytes());data[-5]^=1;image.write_bytes(data)
    corrupt=check(False);assert not corrupt['fixture_valid']
    selected.write_text('-only-testing:AnkiPadUITests/ShareExtensionFlowTests/testSafariSharePersistsUntilExplicitNoteSaveAndDoesNotReopenAfterCancel\n')
    not_required=check(True);assert not not_required['photo_required']
    selected.write_text('-only-testing:AnkiPadUITests/Missing/testUnknown\n');check(False)
print('PASS: photo preflight rejects missing/corrupt pixels and unknown cases, records failures, and skips unrelated fixture dependencies')

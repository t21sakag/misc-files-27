#!/usr/bin/env python3
"""Fail before a long UI journey if its external photo fixture/host is missing."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import time
import zlib

parser=argparse.ArgumentParser()
parser.add_argument('--simulator',required=True)
parser.add_argument('--selections',type=Path,required=True)
parser.add_argument('--output',type=Path,default=Path('build/ui-prerequisites.json'))
args=parser.parse_args()
selected=args.selections.read_text().splitlines()
photo=not selected or any(line.endswith('/testPhotoShareSurvivesConfirmationCancelAndRelaunchBeforeSavingMedia') for line in selected)
report={'photo_required':photo,'fixture_valid':False,'photo_host_installed':False}
args.output.parent.mkdir(parents=True,exist_ok=True)
try:
    groups=json.loads(Path(__file__).with_name('ui-case-groups.json').read_text())
    known={'-only-testing:AnkiPadUITests/'+name+'/'+method for name,methods in groups.items() for method in methods}
    assert all(value in known for value in selected),'Unknown UI prerequisite selection'
    if photo:
        image=Path('build/occlusion-fixture.png').read_bytes()
        assert image[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',image,16)==(512,384),'Missing/wrong image fixture'
        position=8;parts=[]
        while position<len(image):
            size=struct.unpack_from('>I',image,position)[0]
            kind=image[position+4:position+8];data=image[position+8:position+8+size]
            assert len(data)==size and position+12+size<=len(image),'Truncated PNG fixture'
            assert zlib.crc32(kind+data)==struct.unpack_from('>I',image,position+8+size)[0],'PNG checksum mismatch'
            if kind==b'IDAT':parts.append(data)
            position+=12+size
        assert position==len(image)
        assert len(zlib.decompress(b''.join(parts)))==384*(1+512*3),'PNG pixels do not decode'
        report['fixture_valid']=True
        deadline=time.monotonic()+15
        while True:
            result=subprocess.run(['xcrun','simctl','get_app_container',args.simulator,'com.apple.mobileslideshow','app'],capture_output=True,text=True)
            if result.returncode==0:
                report['photo_host_installed']=True
                break
            if time.monotonic()>=deadline:
                report['photo_host_error']=result.stderr.strip()
                raise RuntimeError('Photo host did not become available')
            time.sleep(0.5)
    print('PASS: selected external UI prerequisites '+json.dumps(report))
finally:
    args.output.write_text(json.dumps(report,indent=2)+'\n')

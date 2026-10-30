"""Exercise IPA metadata rejection without needing an Apple SDK or user files."""
import copy
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
verifier = root/'scripts/verify-ipa.py'
bundle = re.search(r"info\['CFBundleIdentifier'\] == '([^']+)'",verifier.read_text())[1]
source = '1'*40
group = 'group.'+bundle+'.shared'
def binary(platform=2, groups=None, xml=True):
    payload = plistlib.dumps({'com.apple.security.application-groups':groups if groups is not None else [group]})
    slot = struct.pack('>II',0xfade7171,8+len(payload))+payload
    signature = struct.pack('>IIIII',0xfade0cc0,20+len(slot),1,5 if xml else 7,20)+slot
    return (struct.pack('<8I',0xfeedfacf,0x100000c,0,2,2,40,0,0)
            +struct.pack('<6I',0x32,24,platform,0x120000,0x1b0000,0)
            +struct.pack('<4I',0x1d,16,72,len(signature))+signature)
main = {'CFBundlePackageType':'APPL','CFBundleIdentifier':bundle, 'UIDeviceFamily':[2], 'MinimumOSVersion':'18.0',
        'CFBundleVersion':'1','CFBundleShortVersionString':'0.2.0','CFBundleExecutable':'Client',
        'CFBundleSupportedPlatforms':['iPhoneOS'],'AnkiPadSourceCommit':source,'StudySharedGroup':group}
share = dict(main,CFBundlePackageType='XPC!',CFBundleIdentifier=bundle+'.share',CFBundleExecutable='ShareExtension',NSExtension={
    'NSExtensionPointIdentifier':'com.apple.share-services',
    'NSExtensionPrincipalClass':'ShareExtension.ShareViewController',
    'NSExtensionAttributes':{'NSExtensionActivationRule':dict(NSExtensionActivationSupportsText=True,**{
        'NSExtensionActivationSupports'+kind+'WithMaxCount':1 for kind in ['File','Image','Movie','WebURL']})}})
app = 'Payload/Client.app/'
extension = app+'PlugIns/ShareExtension.appex/'
widget = app+'PlugIns/StudyWidgets.appex/'
widget_info = dict(main,CFBundlePackageType='XPC!',CFBundleIdentifier=bundle+'.widgets',CFBundleExecutable='StudyWidgets',
                   NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'})
files = {app+'Info.plist':plistlib.dumps(main),app+'Client':binary(),extension+'Info.plist':plistlib.dumps(share),extension+'ShareExtension':binary(),
         widget+'Info.plist':plistlib.dumps(widget_info),widget+'StudyWidgets':binary()}
for language in ['ja','en']:
    files[app+language+'.lproj/Localizable.strings']=b''
    files[extension+language+'.lproj/Localizable.strings']=b''
    files[widget+language+'.lproj/Localizable.strings']=b''
    files[widget+language+'.lproj/WidgetConfiguration.strings']=b''
for name in ['AGPL-3.0.txt','AnkiDroid-GPL-3.0.txt','Anki-NOTICE.txt']:files[app+name]=b'synthetic license fixture'
with tempfile.TemporaryDirectory() as directory:
    ipa=Path(directory)/'fixture.ipa'
    def check(values, success):
        with zipfile.ZipFile(ipa,'w') as archive:
            for key,value in values.items():archive.writestr(key,value)
        result=subprocess.run([sys.executable,'-I',str(verifier),str(ipa),'--source',source],capture_output=True,text=True)
        assert (result.returncode == 0) == success,(success,result.stdout,result.stderr)
    check(files,True)
    for prefix, name in [(extension,'ShareExtension'),(widget,'StudyWidgets')]:
        for replacement in [binary(platform=7),binary(groups=['group.other']),binary(xml=False),binary()[:70],binary()+b'ANKIPAD_UI_TEST_NAMESPACE',binary()+b'widget-probe.json']:
            check(dict(files,**{prefix+name:replacement}),False)
        check({key:value for key,value in files.items() if not key.startswith(prefix)},False)
    modified=copy.deepcopy(share);modified['AnkiPadSourceCommit']='2'*40
    check(dict(files,**{extension+'Info.plist':plistlib.dumps(modified)}),False)
    modified=copy.deepcopy(widget_info);modified['CFBundleVersion']='2'
    check(dict(files,**{widget+'Info.plist':plistlib.dumps(modified)}),False)
    check(dict(files,**{widget+'backend/private.js':b'engine must remain in the main app'}),False)
    check(dict(files,**{app+'private.apkg':b'never distribute test decks'}),False)
    check(dict(files,**{app+'embedded.mobileprovision':b'never upload profiles'}),False)
print('PASS: isolated IPA verification accepts app/share/widget metadata and rejects wrong platform/group, truncation, hooks, missing/mismatched extensions, engine leakage, decks and profiles')

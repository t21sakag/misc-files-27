"""Check native translation coverage and format arguments before any Apple build."""
import importlib.util
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sources', root/'scripts/localization_sources.py')
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)
line_pattern = re.compile(r'^("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");$')
format_pattern = re.compile(r'%(?:[1-9][0-9]*\$)?(?:lld|d|lf|@|%)')


def table(path):
    result = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.startswith('/*'): continue
        match = line_pattern.fullmatch(line)
        assert match, (path, number)
        key, value = map(json.loads, match.groups())
        assert key not in result, (path, key)
        result[key] = value
    return result


resources = root/'ios/AnkiPad/Resources'
ja = table(resources/'ja.lproj/Localizable.strings')
en = table(resources/'en.lproj/Localizable.strings')
assert ja.keys() == en.keys()
for key in ja:
    assert ja[key] == key, ('Japanese fallback changed', key)
    assert en[key].strip() and not sources.is_japanese(en[key]), ('Untranslated English', key)
    assert format_pattern.findall(key) == format_pattern.findall(en[key]), ('Format arguments changed', key)
    assert key.count('{number}') == en[key].count('{number}')

used = set()
occurrences = 0
for path in sorted(path for directory in ['AnkiPad', 'ShareExtension', 'SharedClient', 'StudyWidgets']
                   for path in (root/'ios'/directory).glob('*.swift')):
    text = path.read_text()
    for value in sources.scan(text):
        literal = value['text']
        for expression in value['expressions']:
            literal = literal.replace('\\(' + expression + ')', '')
        if not sources.is_japanese(literal): continue
        if path.name == 'AppText.swift' and value['text'] == '"日本語"': continue  # Language autonym.
        location = (path.name, text.count('\n', 0, value['start'])+1)
        assert text[:value['start']].endswith('AppText.localized('), ('Not localizable', location, value['text'])
        assert not value['raw'] and not value['multiline'], ('Review this literal explicitly', location)
        key = sources.localization_key(value)
        assert key in ja and key in en, ('Missing translation', location, key)
        used.add(key); occurrences += 1
for language in ['ja','en']:
    info = table(resources/(language+'.lproj')/'InfoPlist.strings')
    assert set(info) == {'NSCameraUsageDescription','NSMicrophoneUsageDescription','NSSpeechRecognitionUsageDescription','NSLocalNetworkUsageDescription'}
    if language == 'en': assert not any(sources.is_japanese(value) for value in info.values())
widget_tables = [table(root/'ios/StudyWidgets/Resources'/(language+'.lproj')/'WidgetConfiguration.strings') for language in ['ja','en']]
assert widget_tables[0].keys() == widget_tables[1].keys()
for key, value in widget_tables[1].items():
    assert value == key and not sources.is_japanese(value), ('Widget configuration base key', key)
    assert widget_tables[0][key].strip(), ('Missing Japanese widget configuration', key)
print(f'PASS: {occurrences} native text sites, {len(used)} used keys, {len(ja)} ja/en translations, matching format arguments and permission reasons')

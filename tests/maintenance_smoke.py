from engine_smoke import Engine
from pathlib import Path
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    engine = Engine(root / 'source')
    types = engine.call('NotetypesService.GetNotetypeNames')['entries']
    note = engine.call('NotesService.NewNote', {'ntid': types[0]['id']})
    note['fields'] = ['バックアップの質問', '保存した解答']
    nid = engine.call('NotesService.AddNote', {'note': note, 'deckId': '1'})['noteId']
    backup_folder = root / 'backups'
    backup_folder.mkdir()
    result = engine.call('CollectionService.CreateBackup', {'backupFolder': str(backup_folder), 'force': True, 'waitForCompletion': True})
    backup = next(backup_folder.glob('*.colpkg'))
    engine.call('NotesService.RemoveNotes', {'noteIds': [nid]})
    engine.call('CollectionService.CloseCollection')
    engine.call('ImportExportService.ImportCollectionPackage', {'colPath': str(engine.root / 'collection.anki2'),
        'backupPath': str(backup), 'mediaFolder': str(engine.root / 'collection.media'), 'mediaDb': str(engine.root / 'collection.media.db2')})
    def reopen():
        engine.call('CollectionService.OpenCollection', {'collectionPath': str(engine.root / 'collection.anki2'),
            'mediaFolderPath': str(engine.root / 'collection.media'), 'mediaDbPath': str(engine.root / 'collection.media.db2')})
    reopen()
    assert engine.call('NotesService.GetNote', {'nid': nid})['fields'][0] == 'バックアップの質問'
    package = root / 'export.colpkg'
    engine.call('ImportExportService.ExportCollectionPackage', {'outPath': str(package), 'includeMedia': True})
    assert package.stat().st_size > 0
    reopen()
    preferences = engine.call('ConfigService.GetPreferences')
    preferences.setdefault('reviewing', {})['showRemainingDueCounts'] = False
    preferences['backups']['daily'] = 9
    engine.call('ConfigService.SetPreferences', preferences)
    saved = engine.call('ConfigService.GetPreferences')
    assert not saved['reviewing'].get('showRemainingDueCounts')
    assert saved['backups']['daily'] == 9
    engine.call('MediaService.AddMediaFile', {'desiredName': 'unused.svg', 'data': 'PHN2Zy8+'})
    check = engine.call('MediaService.CheckMedia')
    assert 'unused.svg' in check['unused']
    engine.call('MediaService.TrashMediaFiles', {'fnames': ['unused.svg']})
    assert not (engine.root / 'collection.media' / 'unused.svg').exists()
    engine.call('MediaService.RestoreTrash')
    assert (engine.root / 'collection.media' / 'unused.svg').exists()
    text = root / 'import.tsv'
    text.write_text('CSV question\tCSV answer\n')
    metadata = engine.call('ImportExportService.GetCsvMetadata', {'path': str(text), 'notetypeId': types[0]['id'], 'deckId': '1'})
    imported = engine.call('ImportExportService.ImportCsv', {'path': str(text), 'metadata': metadata})
    assert imported['log']['foundNotes'] == 1, imported
    assert engine.call('SearchService.SearchCards', {'search': '"CSV question"'})['ids']
    engine.call('CollectionService.CheckDatabase')
    engine.close()
print('PASS: backup/restore + collection package export + preferences + media check/trash/restore + CSV import + database check')

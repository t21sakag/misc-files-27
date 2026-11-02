"""Reject missing/corrupt/partial native intent exports before long UI work."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from app_intents_metadata import validate_widget_intents

with tempfile.TemporaryDirectory() as temporary:
    bundle = Path(temporary) / 'StudyWidgets.appex'
    metadata = bundle / 'Metadata.appintents' / 'extract.actionsdata'
    def reject():
        try:
            validate_widget_intents(bundle)
        except ValueError:
            return
        raise AssertionError('An unusable widget configuration export was accepted')
    reject()
    metadata.parent.mkdir(parents=True)
    for raw in ['', '{', '[]', '{}', '{"actions": []}']:
        metadata.write_text(raw)
        reject()
    actions = {
        name: {'fullyQualifiedTypeName': 'StudyWidgets.' + name,
               'parameters': [{'name': parameter, 'isOptional': optional}]}
        for name, parameter, optional in [
            ('ProfileWidgetConfiguration', 'profile', True),
            ('DeckListWidgetConfiguration', 'decks', False),
            ('DeckAnalysisWidgetConfiguration', 'deck', True)]
    }
    valid = {'actions': actions, 'version': 1, 'unrelatedFutureField': {}}
    metadata.write_text(json.dumps(valid))
    assert validate_widget_intents(bundle) == sorted(actions)
    for name in actions:
        variants = []
        missing = deepcopy(valid); del missing['actions'][name]; variants.append(missing)
        foreign = deepcopy(valid); foreign['actions'][name]['fullyQualifiedTypeName'] = 'Other.' + name; variants.append(foreign)
        empty = deepcopy(valid); empty['actions'][name]['parameters'] = []; variants.append(empty)
        duplicate = deepcopy(valid); duplicate['actions'][name]['parameters'] *= 2; variants.append(duplicate)
        changed = deepcopy(valid); changed['actions'][name]['parameters'][0]['isOptional'] = not actions[name]['parameters'][0]['isOptional']; variants.append(changed)
        for value in variants:
            metadata.write_text(json.dumps(value)); reject()
print('PASS: missing/corrupt/partial/foreign/ambiguous widget configuration exports rejected; complete export accepted')

"""Reject widgets whose native configuration intents were not exported."""
import json
from pathlib import Path


def validate_widget_intents(bundle):
    bundle = Path(bundle)
    metadata = bundle / 'Metadata.appintents' / 'extract.actionsdata'
    try:
        content = json.loads(metadata.read_text())
    except (OSError, ValueError) as error:
        raise ValueError(f'Missing or invalid widget intent metadata: {metadata}') from error
    if not isinstance(content, dict) or not isinstance(content.get('actions'), dict):
        raise ValueError(f'Widget intent metadata has no actions: {metadata}')
    expected = {
        'ProfileWidgetConfiguration': ('profile', True),
        'DeckListWidgetConfiguration': ('decks', False),
        'DeckAnalysisWidgetConfiguration': ('deck', True),
    }
    for name, (parameter, optional) in expected.items():
        action = content['actions'].get(name)
        if not isinstance(action, dict) or action.get('fullyQualifiedTypeName') != 'StudyWidgets.' + name:
            raise ValueError(f'Widget configuration intent was not exported: {name}')
        parameters = action.get('parameters')
        if not isinstance(parameters, list):
            raise ValueError(f'Widget configuration has no parameters: {name}')
        matches = [value for value in parameters if isinstance(value, dict) and value.get('name') == parameter]
        if len(matches) != 1 or matches[0].get('isOptional') is not optional:
            raise ValueError(f'Widget configuration parameter is missing or ambiguous: {name}.{parameter}')
    return sorted(expected)

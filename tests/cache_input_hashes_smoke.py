"""Input scope/invalidation regression for cache keys after restoring huge outputs."""
import importlib.util
from pathlib import Path
import tempfile

script = Path(__file__).resolve().parents[1] / 'scripts/cache-input-hashes.py'
spec = importlib.util.spec_from_file_location('cache_inputs', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    for name in set(module.BRIDGE + module.CARGO + ['ios/project.yml', 'native/src/lib.rs']):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(name)
    baseline = module.hashes(root)
    output = root / 'native/target/cache/file'
    output.parent.mkdir(parents=True)
    output.write_text('Restored outputs must not participate')
    assert module.hashes(root) == baseline
    (root / 'ios/project.yml').write_text('Changed Xcode settings')
    project = module.hashes(root)
    assert project['bridge'] == baseline['bridge'] and project['cargo'] == baseline['cargo']
    assert project['simulator'] != baseline['simulator']
    (root / 'native/src/lib.rs').write_text('Changed bridge')
    bridge = module.hashes(root)
    assert bridge['bridge'] != project['bridge'] and bridge['simulator'] != project['simulator']
    assert bridge['cargo'] == project['cargo']
    (root / 'native/Cargo.lock').unlink()
    try:
        module.hashes(root)
    except FileNotFoundError:
        pass
    else:
        raise AssertionError('Missing required input silently produced a cache key')
print('PASS: native/Xcode invalidation; restored outputs excluded; missing inputs rejected')

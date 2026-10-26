from engine_smoke import Engine, lib, unpack
from pathlib import Path
import sqlite3
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory) / 'eta'
    engine = Engine(root)
    counts = {'cutoffMillis': 100000, 'new': 5, 'learning': 3, 'review': 7}
    assert engine.call('_droid/eta', counts)['minutes'] == 5  # no history: 20 seconds/rep
    engine.close()
    # Controlled revlog fixture distinguishes new, learning/relearning, review,
    # and a record outside the ten-day window. No user collection is involved.
    records = [
        (100001, 0, 1, 1000), (100002, 0, 3, 3000),
        (100003, 1, 3, 4000), (100004, 3, 1, 8000),
        (100005, 2, 4, 10000), (100006, 2, 1, 20000),
        (99999, 0, 1, 999999),
    ]
    with sqlite3.connect(root / 'collection.anki2') as db:
        for record_id, kind, ease, milliseconds in records:
            db.execute('insert into revlog (id,cid,usn,ease,ivl,lastIvl,factor,time,type) values (?,1,0,?,1,1,2500,?,?)', (record_id,ease,milliseconds,kind))
    engine = Engine(root)
    # AnkiDroid: current reps 97000 ms, future failures 5+2+1 at 15000 ms.
    assert engine.call('_droid/eta', counts)['minutes'] == 4
    assert engine.call('_droid/eta', dict(counts, cutoffMillis=200000))['minutes'] == 5
    assert engine.call('_droid/eta', dict(counts, new=0, learning=0, review=0))['minutes'] == 0
    invalid = unpack(lib.ap_call(engine.handle, b'_droid/eta', b'{"cutoffMillis":0,"new":-1,"learning":0,"review":0}'))
    assert 'error' in invalid
    # Extra SQL is never accepted as a command: only the fixed aggregate is run.
    assert engine.call('_droid/eta', dict(counts, sql='drop table revlog'))['minutes'] == 4
    engine.close()
print('PASS: AnkiDroid ETA empty-history defaults + per-type success/time + future failures + cutoff + fixed read-only SQL boundary')

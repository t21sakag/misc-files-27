//! Read local collection timestamps without a network status request.
use anki::backend::Backend;
use serde_json::{Value, json};

pub fn status(backend: &Backend) -> Result<Value, String> {
    let query = json!({"kind": "query", "sql": "select mod, scm, ls, exists(select 1 from cards) from col", "args": [], "first_row_only": true});
    let bytes = backend.run_db_command_bytes(&serde_json::to_vec(&query).map_err(|e| e.to_string())?)
        .map_err(|_| "Could not read local sync state")?;
    let rows: Vec<Vec<i64>> = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    let row = rows.first().filter(|r| r.len() == 4).ok_or("Missing local sync timestamps")?;
    let never_synced = row[2] == 0;
    // A never-synced empty collection cannot know the server state. Report its
    // first-sync status separately, rather than pretending it is synchronized.
    let changes = if never_synced { row[3] != 0 } else { row[0] > row[2] || row[1] > row[2] };
    Ok(json!({"neverSynced": never_synced, "hasChanges": changes}))
}

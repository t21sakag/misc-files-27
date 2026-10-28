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
    Ok(json!({"neverSynced": never_synced, "hasChanges": changes, "modification": row[0].to_string()}))
}

/// Mark the schema as modified so the next sync must replace one side, like
/// upstream `modSchema(check = false)` from the one-way sync preference.
pub fn force_one_way(backend: &Backend) -> Result<Value, String> {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e| e.to_string())?.as_millis() as i64;
    let run = |request: Value| backend.run_db_command_bytes(&serde_json::to_vec(&request).map_err(|e| e.to_string())?)
        .map(|_| ()).map_err(|_| "Could not request a one-way sync".to_string());
    run(json!({"kind": "begin"}))?;
    let update = json!({"kind": "query", "sql": "update col set scm=?, mod=?", "args": [now, now], "first_row_only": false});
    if let Err(error) = run(update) {
        let _ = run(json!({"kind": "rollback"}));
        return Err(error);
    }
    run(json!({"kind": "commit"}))?;
    Ok(json!({"schemaModified": now.to_string()}))
}

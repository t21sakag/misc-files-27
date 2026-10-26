// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (c) 2022 Ankitects Pty Ltd <https://apps.ankiweb.net>
// Adapted from AnkiDroid v2.26.0alpha7 libanki Scheduler.eta().
//! Legacy ETA calculation used by AnkiDroid v2.26.0alpha7 Scheduler.eta().
//! Read the backend's existing connection with fixed SQL; never accept UI SQL.
use anki::backend::Backend;
use serde_json::{json, Value};

pub fn estimate(backend: &Backend, request: &str) -> Result<Value, String> {
    let input: Value = serde_json::from_str(request).map_err(|e| e.to_string())?;
    let cutoff = input["cutoffMillis"].as_i64().ok_or("missing ETA cutoff")?;
    let count = |key: &str| -> Result<u64, String> {
        input[key].as_u64().filter(|n| *n <= u32::MAX as u64).ok_or_else(|| format!("invalid ETA count: {key}"))
    };
    let new = count("new")?;
    let learning = count("learning")?;
    let review = count("review")?;
    let query = json!({"kind": "query", "sql": "select avg(case when type=0 then time end), avg(case when type in (1,3) then case when ease>1 then 1.0 else 0.0 end end), avg(case when type in (1,3) then time end), avg(case when type=2 then case when ease>1 then 1.0 else 0.0 end end), avg(case when type=2 then time end) from revlog where id > ?", "args": [cutoff], "first_row_only": true});
    let bytes = backend.run_db_command_bytes(&serde_json::to_vec(&query).map_err(|e| e.to_string())?)
        .map_err(|_| "Could not read review-time history")?;
    let rows: Vec<Vec<Option<f64>>> = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    let value = |index: usize, fallback: f64| -> f64 {
        rows.first().and_then(|row| row.get(index)).copied().flatten().filter(|v| *v != 0.0).unwrap_or(fallback)
    };
    let new_time = value(0, 20000.0);
    let review_rate = value(1, 1.0);
    let review_time = value(2, 20000.0);
    let relearn_rate = value(3, 1.0);
    let relearn_time = value(4, 20000.0);
    let mut to_relearn = new + ((1.0 - relearn_rate) * learning as f64).ceil() as u64
        + ((1.0 - review_rate) * review as f64).ceil() as u64;
    let bounded_rate = relearn_rate.max(0.05);
    let mut future = 0_u64;
    loop {
        let failures = ((1.0 - bounded_rate) * to_relearn as f64) as u64;
        future += failures;
        to_relearn = failures;
        if to_relearn <= 1 { break; }
    }
    let millis = new_time * new as f64 + relearn_time * learning as f64
        + review_time * review as f64 + relearn_time * future as f64;
    Ok(json!({"minutes": (millis / 60000.0).round() as i64}))
}

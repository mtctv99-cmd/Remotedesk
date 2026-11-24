//! Auto-publish the newest client package found next to the Manager.
//!
//! The console already serves the newest `deskagent-*-install.exe` / `.zip`
//! from `/data` (or the working directory). This loop closes the last gap:
//! after a release file is copied there, it fills the `update_*` settings that
//! clients poll from `/api/version/latest`, so every installed client sees the
//! new build on its next one-minute auto-update tick without an admin action.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use ring::digest::{digest, SHA256};

use crate::{db, AppState};

const SCAN_DIRS: [&str; 2] = ["/data", "."];
const POLL_INTERVAL: Duration = Duration::from_secs(30);
const SETTING_PUBLISHED_SHA: &str = "deploy_published_sha";

fn is_release_file(name: &str) -> bool {
    let name = name.to_lowercase();
    (name.starts_with("deskagent-") && name.ends_with("-install.exe")) || name.ends_with(".zip")
}

/// Newest release file by mtime, or None when nothing matches.
fn newest_release() -> Option<(PathBuf, SystemTime)> {
    let mut found: Option<(PathBuf, SystemTime)> = None;
    for dir in SCAN_DIRS {
        let Ok(entries) = std::fs::read_dir(dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let name = path
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            if !is_release_file(&name) {
                continue;
            }
            let mtime = entry
                .metadata()
                .and_then(|m| m.modified())
                .unwrap_or(UNIX_EPOCH);
            if found.as_ref().map_or(true, |(_, best)| mtime > *best) {
                found = Some((path, mtime));
            }
        }
    }
    found
}

/// Parse a version from `deskagent-<version>-install.exe`, else from a
/// `<file>.version` sidecar written by the packaging script.
fn version_for(path: &Path) -> Option<String> {
    let name = path.file_name()?.to_string_lossy().to_lowercase();
    for suffix in ["-install.exe", "-install.zip"] {
        if name.starts_with("deskagent-") && name.ends_with(suffix) {
            let inner = &name["deskagent-".len()..name.len() - suffix.len()];
            if !inner.is_empty() && inner.chars().any(|c| c.is_ascii_digit()) {
                return Some(inner.to_string());
            }
        }
    }
    let sidecar = PathBuf::from(format!("{}.version", path.to_string_lossy()));
    let raw = std::fs::read_to_string(sidecar).ok()?;
    let version = raw.trim();
    if version.is_empty() {
        None
    } else {
        Some(version.to_string())
    }
}

fn sha256_hex(path: &Path) -> Result<String, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let hash = digest(&SHA256, &bytes);
    Ok(hash
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

fn publish_once(state: &AppState) -> Result<(), String> {
    let Some((path, _mtime)) = newest_release() else {
        return Ok(());
    };
    let version = version_for(&path)
        .ok_or_else(|| format!("no version for {} (add a .version sidecar)", path.display()))?;
    let sha = sha256_hex(&path)?;

    let conn = state.db.lock().map_err(|_| "database mutex poisoned")?;
    let all = db::get_all_settings(&conn).map_err(|e| e.to_string())?;
    if all.get(SETTING_PUBLISHED_SHA).map(String::as_str) == Some(sha.as_str()) {
        return Ok(());
    }

    let notes = format!(
        "Auto-published {} ({})",
        path.file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default(),
        version
    );
    db::set_setting(&conn, "update_latest", &version).map_err(|e| e.to_string())?;
    db::set_setting(&conn, "update_url", "/download/client").map_err(|e| e.to_string())?;
    db::set_setting(&conn, "update_sha256", &sha).map_err(|e| e.to_string())?;
    db::set_setting(&conn, "update_notes", &notes).map_err(|e| e.to_string())?;
    db::set_setting(&conn, SETTING_PUBLISHED_SHA, &sha).map_err(|e| e.to_string())?;
    eprintln!(
        "autodeploy: published {} (version {}, sha256 {})",
        path.display(),
        version,
        sha
    );
    Ok(())
}

/// Background loop: republish whenever the newest package changes.
pub async fn watch_loop(state: Arc<AppState>) {
    let mut tick = tokio::time::interval(POLL_INTERVAL);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tick.tick().await;
        if let Err(e) = publish_once(&state) {
            eprintln!("autodeploy: {e}");
        }
    }
}

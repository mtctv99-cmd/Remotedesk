// Owned version feed (WS-6 + signed follow-up): `GET /api/version`.
//
// Public metadata only (same sensitivity as manager's /api/discover): the
// fields come from the shared `settings` table, which the admin edits through
// manager's existing /settings console — no new auth surface, no signing
// oracle. Keys: `update_latest` (e.g. "1.5.1"), `update_min_supported`,
// `update_url`, `update_sha256`, `update_notes`.
//
// Trust model: `update_signature` is Ed25519 over the newline-joined
// `latest/min_supported/url/sha256`, made by the manager server key (same
// `settings.server_key` the enroll trust anchor publishes). The client MUST
// verify the signature against its staged `v2-server-key` anchor and refuse
// unsigned/mismatched manifests. An empty `update_latest` is 404
// (fail-closed: no phantom updates). Unsigned legacy rows stay fail-closed
// on the client.

use axum::{extract::State, http::StatusCode, routing::get, Json, Router};
use serde::Serialize;
use std::sync::{Arc, Mutex};

pub struct VersionState {
    pub db: Mutex<rusqlite::Connection>,
}

pub type Shared = Arc<VersionState>;

#[derive(Serialize)]
struct VersionManifest {
    latest: String,
    min_supported: String,
    url: String,
    sha256: String,
    notes: String,
    signature: String,
}

async fn get_version(
    State(state): State<Shared>,
) -> Result<Json<VersionManifest>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "database mutex poisoned".to_string(),
        )
    })?;
    let get = |k: &str| -> String {
        crate::db::get_setting(&conn, k)
            .unwrap_or(None)
            .unwrap_or_default()
    };
    let latest = get("update_latest");
    if latest.trim().is_empty() {
        return Err((StatusCode::NOT_FOUND, "no published version".to_string()));
    }
    Ok(Json(VersionManifest {
        latest,
        min_supported: get("update_min_supported"),
        url: get("update_url"),
        sha256: get("update_sha256"),
        notes: get("update_notes"),
        signature: get("update_signature"),
    }))
}

pub fn router(state: Shared) -> Router {
    Router::new().route("/api/version", get(get_version)).with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    fn state_with(settings: &[(&str, &str)]) -> Shared {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0);",
        )
        .unwrap();
        for (k, v) in settings {
            conn.execute(
                "INSERT INTO settings (key, value) VALUES (?1, ?2)",
                rusqlite::params![k, v],
            )
            .unwrap();
        }
        Arc::new(VersionState {
            db: Mutex::new(conn),
        })
    }

    #[tokio::test]
    async fn serves_manifest_and_404_when_unset() {
        let app = router(state_with(&[
            ("update_latest", "1.5.1"),
            ("update_url", "https://example.invalid/dl"),
            ("update_signature", "sig-test"),
        ]));
        let res = app
            .oneshot(
                Request::get("/api/version")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 64 * 1024).await.unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(v["latest"], "1.5.1");
        assert_eq!(v["signature"], "sig-test");

        let app = router(state_with(&[]));
        let res = app
            .oneshot(
                Request::get("/api/version")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::NOT_FOUND);
    }
}

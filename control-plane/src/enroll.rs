// Enrollment / key-ceremony HTTP API.
//
// This replaces the manual `id_ed25519.pub` paste flow (server-runbook.md):
// an admin mints a SINGLE-USE invite code, the fresh device claims it, and
// gets back everything it needs in one response — device token, server trust
// anchor, signaling/relay addresses. The trust anchor is `settings.deploy_pubkey`
// (fallback `settings.server_key`), the same key the manager uses to sign the
// version manifest, so enrollment never invents a second root of trust.
//
// POST /api/enroll/invite  (admin: `Authorization: Bearer <admin token>`)
//   -> { "invite": "<64 hex>" }           (shown once; only the hash is stored)
// POST /api/enroll/claim   (no auth: the invite IS the auth, single-use + TTL)
//   { "invite", "peer_id", "hostname", "os", "ed25519_pubkey" }
//   -> { "device_token", "client_id", "server_key", "signaling", "relay" }
//   The device token uses the manager scheme (hash at rest, bound to the
//   client row, never re-issued here); the client then uses X-Device-Token
//   against manager exactly like a console-registered device.

use axum::{extract::{ConnectInfo, State}, http::StatusCode, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub struct EnrollState {
    pub db: Mutex<rusqlite::Connection>,
    pub signaling_advertise: String,
    pub relay_advertise: String,
    pub claim_limits: Mutex<HashMap<IpAddr, (u32, Instant)>>,
}

const CLAIM_MAX_FAILURES: u32 = 10;
const CLAIM_WINDOW: Duration = Duration::from_secs(300);

fn claim_ip(addr: Option<ConnectInfo<SocketAddr>>) -> Option<IpAddr> {
    addr.map(|ConnectInfo(a)| a.ip())
}

fn claim_blocked(state: &Shared, ip: IpAddr) -> bool {
    let now = Instant::now();
    let mut map = state.claim_limits.lock().unwrap_or_else(|e| e.into_inner());
    map.retain(|_, (_, start)| now.duration_since(*start) <= CLAIM_WINDOW);
    map.get(&ip)
        .map(|(n, start)| *n >= CLAIM_MAX_FAILURES && now.duration_since(*start) <= CLAIM_WINDOW)
        .unwrap_or(false)
}

fn claim_record_failure(state: &Shared, ip: IpAddr) {
    let now = Instant::now();
    let mut map = state.claim_limits.lock().unwrap_or_else(|e| e.into_inner());
    map.retain(|_, (_, start)| now.duration_since(*start) <= CLAIM_WINDOW);
    let entry = map.entry(ip).or_insert((0, now));
    if now.duration_since(entry.1) > CLAIM_WINDOW {
        *entry = (1, now);
    } else {
        entry.0 += 1;
    }
}

pub type Shared = Arc<EnrollState>;

fn internal_error<E: std::fmt::Display>(e: E) -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, format!("internal error: {e}"))
}

fn db_poisoned() -> (StatusCode, String) {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        "database mutex poisoned".to_string(),
    )
}

fn bearer_token(headers: &axum::http::HeaderMap) -> Option<String> {
    headers
        .get(axum::http::header::AUTHORIZATION)?
        .to_str()
        .ok()
        .filter(|h| h.starts_with("Bearer "))
        .map(|h| h[7..].to_string())
}

#[derive(Serialize)]
struct InviteResponse {
    invite: String,
    expires_in: i64,
}

async fn create_invite(
    State(state): State<Shared>,
    headers: axum::http::HeaderMap,
) -> Result<Json<InviteResponse>, (StatusCode, String)> {
    let token = bearer_token(&headers)
        .ok_or((StatusCode::UNAUTHORIZED, "Unauthorized".to_string()))?;
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    if !crate::db::check_admin_token(&conn, &token).map_err(internal_error)? {
        return Err((StatusCode::UNAUTHORIZED, "Unauthorized".to_string()));
    }
    // 32 random bytes hex (64 chars): single-use, shown once.
    let invite = {
        use ring::rand::{SecureRandom, SystemRandom};
        let rng = SystemRandom::new();
        let mut bytes = [0u8; 32];
        rng.fill(&mut bytes).map_err(|_| internal_error("CSPRNG failure"))?;
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    };
    crate::db::create_invite(&conn, &crate::auth::hash_token(&invite))
        .map_err(internal_error)?;
    Ok(Json(InviteResponse {
        invite,
        expires_in: crate::db::INVITE_TTL_SECS,
    }))
}

#[derive(Deserialize)]
struct ClaimRequest {
    invite: String,
    peer_id: String,
    #[serde(default)]
    hostname: String,
    #[serde(default)]
    os: String,
    #[serde(default)]
    ed25519_pubkey: String,
}

#[derive(Serialize)]
struct ClaimResponse {
    device_token: String,
    client_id: String,
    server_key: String,
    signaling: String,
    relay: String,
}

async fn claim_invite(
    State(state): State<Shared>,
    addr: Option<ConnectInfo<SocketAddr>>,
    Json(req): Json<ClaimRequest>,
) -> Result<Json<ClaimResponse>, (StatusCode, String)> {
    if let Some(ip) = claim_ip(addr) {
        if claim_blocked(&state, ip) {
            return Err((StatusCode::TOO_MANY_REQUESTS, "too many attempts".to_string()));
        }
    }
    if req.peer_id.is_empty() || req.peer_id.len() > 64 || req.invite.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "bad request".to_string()));
    }
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    // Single atomic consume: unknown/used/expired are indistinguishable.
    if !crate::db::consume_invite(&conn, &crate::auth::hash_token(&req.invite))
        .map_err(internal_error)?
    {
        if let Some(ip) = claim_ip(addr) {
            claim_record_failure(&state, ip);
        }
        // ponytail: counts failures per source IP in-memory only; add when
        // enroll leaves loopback (shared counter or per-invite backoff).
        return Err((StatusCode::UNAUTHORIZED, "Unauthorized".to_string()));
    }
    // One identity namespace with manager: the v2 peer_id IS the client id.
    crate::db::ensure_client(
        &conn,
        &req.peer_id,
        &req.hostname,
        &req.os,
        &req.ed25519_pubkey,
    )
    .map_err(internal_error)?;
    // Mint the device token (manager scheme: hash at rest, bound, one-time).
    let device_token = crate::auth::random_hex().map_err(internal_error)?
        + &crate::auth::random_hex().map_err(internal_error)?;
    crate::db::create_device_token(
        &conn,
        &crate::auth::hash_token(&device_token),
        &req.peer_id,
    )
    .map_err(internal_error)?;
    let server_key = trust_anchor(&conn).map_err(internal_error)?;
    if server_key.is_empty() {
        // Fail-closed: without the trust anchor there is nothing to enroll
        // against (manager publishes it from DESKAGENT_SERVER_PRIVKEY).
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "server trust anchor not configured".to_string(),
        ));
    }
    Ok(Json(ClaimResponse {
        device_token,
        client_id: req.peer_id,
        server_key,
        signaling: state.signaling_advertise.clone(),
        relay: state.relay_advertise.clone(),
    }))
}

/// Trust anchor the enroll response publishes: `deploy_pubkey` wins so the
/// anchor always matches the key that signs the version manifest; falls back
/// to legacy `server_key` when deploy_pubkey is unset.
fn trust_anchor(conn: &rusqlite::Connection) -> rusqlite::Result<String> {
    let deploy = crate::db::get_setting(conn, "deploy_pubkey")?.unwrap_or_default();
    if !deploy.trim().is_empty() {
        return Ok(deploy);
    }
    Ok(crate::db::get_setting(conn, "server_key")?.unwrap_or_default())
}

pub fn router(state: Shared) -> Router {
    Router::new()
        .route("/api/enroll/invite", post(create_invite))
        .route("/api/enroll/claim", post(claim_invite))
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use tower::ServiceExt;

    fn state() -> Shared {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE clients (id TEXT PRIMARY KEY, hostname TEXT NOT NULL DEFAULT '', os TEXT NOT NULL DEFAULT '', os_version TEXT NOT NULL DEFAULT '', arch TEXT NOT NULL DEFAULT '', ip TEXT NOT NULL DEFAULT '', version TEXT NOT NULL DEFAULT '', last_seen INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL DEFAULT 0);
             CREATE TABLE admin_tokens (token TEXT PRIMARY KEY, created_at INTEGER NOT NULL DEFAULT 0);
             CREATE TABLE device_tokens (token_hash TEXT PRIMARY KEY, client_id TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL DEFAULT 0);
             CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0);
             CREATE TABLE enroll_invites (code_hash TEXT PRIMARY KEY, created_at INTEGER NOT NULL DEFAULT 0, used_at INTEGER);",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO admin_tokens (token, created_at) VALUES (?1, ?2)",
            rusqlite::params![crate::auth::hash_token("tok_admin"), crate::db::now()],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO settings (key, value) VALUES ('server_key', 'ANCHOR')",
            [],
        )
        .unwrap();
        Arc::new(EnrollState {
            db: Mutex::new(conn),
            claim_limits: Mutex::new(HashMap::new()),
            signaling_advertise: "sig:34116".into(),
            relay_advertise: "relay:34117".into(),
        })
    }

    #[test]
    fn claim_failure_limit_blocks_after_ten_attempts() {
        let state = state();
        let ip = "192.0.2.1".parse().unwrap();
        for _ in 0..CLAIM_MAX_FAILURES {
            assert!(!claim_blocked(&state, ip));
            claim_record_failure(&state, ip);
        }
        assert!(claim_blocked(&state, ip));
    }

    #[tokio::test]
    async fn invite_claim_single_use_flow() {
        let app = router(state());
        // No auth -> 401.
        let res = app
            .clone()
            .oneshot(Request::post("/api/enroll/invite").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
        // Admin bearer -> invite.
        let res = app
            .clone()
            .oneshot(
                Request::post("/api/enroll/invite")
                    .header("authorization", "Bearer tok_admin")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let invite = v["invite"].as_str().unwrap().to_string();
        assert_eq!(invite.len(), 64);
        // Claim -> device token + anchor + addrs.
        let claim = serde_json::json!({"invite": invite, "peer_id": "123456789", "hostname": "h", "os": "win", "ed25519_pubkey": "pk"});
        let res = app
            .clone()
            .oneshot(
                Request::post("/api/enroll/claim")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_vec(&claim).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(v["server_key"], "ANCHOR");
    }

    #[tokio::test]
    async fn claim_prefers_deploy_pubkey_anchor() {
        let st = state();
        {
            let conn = st.db.lock().unwrap();
            conn.execute(
                "INSERT INTO settings (key, value) VALUES ('deploy_pubkey', 'DEPLOY_ANCHOR') ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [],
            )
            .unwrap();
        }
        let app = router(st);
        let res = app
            .clone()
            .oneshot(
                Request::post("/api/enroll/invite")
                    .header("authorization", "Bearer tok_admin")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let invite = v["invite"].as_str().unwrap().to_string();
        let claim = serde_json::json!({"invite": invite, "peer_id": "abc", "hostname": "h", "os": "win", "ed25519_pubkey": "pk"});
        let res = app
            .clone()
            .oneshot(
                Request::post("/api/enroll/claim")
                    .header("content-type", "application/json")
                    .body(Body::from(serde_json::to_vec(&claim).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1024 * 1024).await.unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(v["server_key"], "DEPLOY_ANCHOR");
        assert_eq!(v["client_id"], "abc");
        assert!(!v["device_token"].as_str().unwrap().is_empty());
    }
}

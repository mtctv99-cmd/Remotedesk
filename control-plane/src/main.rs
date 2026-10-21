// DeskAgent owned control plane: v2 signaling + blind relay + enrollment.
//
// Three listeners, one shared SQLite file (see db.rs for the sharing contract):
// - signaling  (TCP, default 0.0.0.0:34116, ALPN deskagent-sig/2 semantics)
// - relay      (TCP, default 0.0.0.0:34117, ALPN deskagent-relay/2 envelope)
// - enroll API (HTTP, default 127.0.0.1:34118 — loopback on purpose: put it
//   behind the same reverse proxy / VPN as manager :8080 in production)
//
// Env:
// - DESKAGENT_CONTROL_DB          shared SQLite path (default "manager.db")
// - DESKAGENT_CONTROL_BIND_SIG    (default "0.0.0.0:34116")
// - DESKAGENT_CONTROL_BIND_RELAY  (default "0.0.0.0:34117")
// - DESKAGENT_CONTROL_BIND_API    (default "127.0.0.1:34118")
// - DESKAGENT_CONTROL_RELAY_ADVERTISE  public "ip:34117" handed to clients
//   (default "127.0.0.1:34117"; NEVER advertise a container-internal IP)
// - DESKAGENT_CONTROL_SIG_ADVERTISE    public "ip:34116" handed to clients
//
// The trust anchor is NOT generated here: manager publishes settings.server_key
// from DESKAGENT_SERVER_PRIVKEY, and enrollment refuses to run until that key
// exists (fail-closed). Rotating the anchor is manager's job; this service
// only reads it.

mod auth;
mod db;
mod enroll;
mod relay;
mod signaling;
mod version;

use std::sync::{Arc, Mutex};

#[tokio::main]
async fn main() {
    let db_path =
        std::env::var("DESKAGENT_CONTROL_DB").unwrap_or_else(|_| "manager.db".to_string());
    let bind_sig = std::env::var("DESKAGENT_CONTROL_BIND_SIG")
        .unwrap_or_else(|_| "0.0.0.0:34116".to_string());
    let bind_relay = std::env::var("DESKAGENT_CONTROL_BIND_RELAY")
        .unwrap_or_else(|_| "0.0.0.0:34117".to_string());
    let bind_api = std::env::var("DESKAGENT_CONTROL_BIND_API")
        .unwrap_or_else(|_| "127.0.0.1:34118".to_string());
    let relay_adv = std::env::var("DESKAGENT_CONTROL_RELAY_ADVERTISE")
        .unwrap_or_else(|_| "127.0.0.1:34117".to_string());
    let sig_adv = std::env::var("DESKAGENT_CONTROL_SIG_ADVERTISE")
        .unwrap_or_else(|_| "127.0.0.1:34116".to_string());

    let conn =
        db::open(&db_path).unwrap_or_else(|e| panic!("cannot open shared db {db_path}: {e}"));
    match db::get_setting(&conn, "server_key").unwrap_or(None) {
        Some(k) if !k.is_empty() => eprintln!("trust anchor: settings.server_key present"),
        _ => eprintln!(
            "CẢNH BÁO / WARNING: settings.server_key chưa có (manager chưa publish từ \
             DESKAGENT_SERVER_PRIVKEY) — enrollment sẽ từ chối cho tới khi key xuất hiện."
        ),
    }
    drop(conn);

    let enroll_state = Arc::new(enroll::EnrollState {
        claim_limits: Mutex::new(std::collections::HashMap::new()),
        db: Mutex::new(
            db::open(&db_path).unwrap_or_else(|e| panic!("cannot reopen shared db: {e}")),
        ),
        signaling_advertise: sig_adv,
        relay_advertise: relay_adv.clone(),
    });

    let api = enroll::router(enroll_state).merge(version::router(Arc::new(
        version::VersionState {
            db: Mutex::new(
                db::open(&db_path).unwrap_or_else(|e| panic!("cannot reopen shared db: {e}")),
            ),
        },
    )));
    let api_listener = tokio::net::TcpListener::bind(&bind_api)
        .await
        .unwrap_or_else(|e| panic!("cannot bind enroll api {bind_api}: {e}"));
    eprintln!("enroll api on http://{bind_api} (loopback default; proxy it like manager)");
    tokio::spawn(async move {
        axum::serve(
            api_listener,
            api.into_make_service_with_connect_info::<std::net::SocketAddr>(),
        )
        .await
        .unwrap_or_else(|e| panic!("enroll api error: {e}"));
    });

    let relay_bind = bind_relay.clone();
    tokio::spawn(async move {
        relay::serve(&relay_bind)
            .await
            .unwrap_or_else(|e| panic!("relay error: {e}"));
    });

    signaling::serve(&bind_sig, &relay_adv)
        .await
        .unwrap_or_else(|e| panic!("signaling error: {e}"));
}

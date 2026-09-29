// DeskAgent manager: standalone axum server (SQLite + client API + AI chat
// proxy + admin console). Runs as its own workspace, outside the rustdesk one.

mod ai;
mod db;
mod routes;

use std::sync::{Arc, Mutex};

use rusqlite::Connection;

use crate::ai::AiConfig;

/// State shared with all handlers.
pub struct AppState {
    /// SQLite connection; short synchronous queries behind a std mutex
    /// (never held across .await in handlers).
    pub db: Mutex<Connection>,
    /// AI proxy config, validated once at startup.
    pub ai: AiConfig,
}

#[tokio::main]
async fn main() {
    // DB file next to the working directory; bootstrap failures abort.
    let conn = Connection::open("manager.db")
        .unwrap_or_else(|e| panic!("cannot open manager.db: {e}"));
    db::init(&conn).unwrap_or_else(|e| panic!("cannot init schema: {e}"));

    // Startup validation via ai::validate_outbound_url (inside from_env):
    // invalid config only disables the bot, the server still runs.
    let ai = AiConfig::from_env();
    if ai.is_configured() {
        eprintln!("AI proxy enabled: endpoint={} model={}", ai.url, ai.model);
    } else {
        eprintln!("AI bot disabled: {}", ai.reason);
    }

    let state = Arc::new(AppState { db: Mutex::new(conn), ai });

    let bind =
        std::env::var("DESKAGENT_MANAGER_BIND").unwrap_or_else(|_| "0.0.0.0:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .unwrap_or_else(|e| panic!("cannot bind {bind}: {e}"));
    eprintln!("deskagent-manager listening on http://{bind}");

    axum::serve(listener, routes::router(state))
        .await
        .unwrap_or_else(|e| panic!("server error: {e}"));
}

// DeskAgent manager: standalone axum server (SQLite + client API + AI chat
// proxy + admin console). Runs as its own workspace, outside the rustdesk one.

mod ai;
mod auth;
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
    /// The admin credential of the API.
    pub admin: auth::AdminAuth,
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

    let admin = auth::AdminAuth::from_env();
    if admin.is_enabled() {
        eprintln!("admin api enabled");
    } else {
        eprintln!(
            "admin api DISABLED: set DESKAGENT_MANAGER_ADMIN_TOKEN to enable the console \
             and the job dispatch"
        );
    }

    let state = Arc::new(AppState {
        db: Mutex::new(conn),
        ai,
        admin,
    });

    // Loopback by default: the manager hands out device tokens and runs
    // commands on the clients, so it must not listen on the whole network
    // unless the operator asks for it.
    let bind = std::env::var("DESKAGENT_MANAGER_BIND")
        .unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .unwrap_or_else(|e| panic!("cannot bind {bind}: {e}"));
    eprintln!("deskagent-manager listening on http://{bind}");

    axum::serve(listener, routes::router(state))
        .await
        .unwrap_or_else(|e| panic!("server error: {e}"));
}

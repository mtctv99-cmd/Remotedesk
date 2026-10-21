// DeskAgent manager: standalone axum server (SQLite + client API + AI chat
// proxy + admin console). Runs as its own standalone workspace.

mod ai;
pub mod crypto;
mod db;
mod routes;

use std::sync::{Arc, Mutex};
use std::time::Duration;

use rusqlite::Connection;

use crate::ai::AiConfig;

/// One-time file holding the auto-generated admin password until the first
/// successful admin login (deleted by the login handler afterwards).
pub const BOOTSTRAP_PASS_FILE: &str = "manager_admin_password.txt";

/// SQLite database file (also the source for the automatic backup below).
const DB_FILE: &str = "manager.db";
/// Rolling backup target, refreshed at most once per 24h.
const DB_BACKUP_FILE: &str = "manager.db.bak-auto";
/// Retention window for jobs/results/conversations/messages.
const RETENTION_INTERVAL: Duration = Duration::from_secs(6 * 3600);
/// Backup cadence.
const BACKUP_INTERVAL: Duration = Duration::from_secs(24 * 3600);
/// A backup older than this is considered stale and replaced.
const BACKUP_MAX_AGE: Duration = Duration::from_secs(24 * 3600);

/// State shared with all handlers.
pub struct AppState {
    /// SQLite connection; short synchronous queries behind a std mutex
    /// (never held across .await in handlers).
    pub db: Mutex<Connection>,
    /// AI proxy config, validated once at startup.
    pub ai: AiConfig,
    /// Configured admin username.
    pub admin_user: String,
    /// Configured admin password.
    pub admin_pass: String,
    /// Ed25519 private key seed for signing deploy jobs.
    pub server_privkey: String,
    /// Shared token clients must present on /api/client/* and /api/conversations/*.
    /// Empty = client API authentication disabled (dev mode only).
    pub client_token: String,
}

/// True when DB_BACKUP_FILE is missing or older than BACKUP_MAX_AGE.
fn backup_is_stale() -> bool {
    match std::fs::metadata(DB_BACKUP_FILE).and_then(|m| m.modified()) {
        Ok(mtime) => match mtime.elapsed() {
            Ok(age) => age >= BACKUP_MAX_AGE,
            Err(_) => true, // clock went backwards — safer to re-copy
        },
        Err(_) => true, // missing or unreadable
    }
}

/// Background maintenance: retention every 6h (first tick at startup) and a
/// cheap DB backup every 24h.
///
/// [Note]
/// The backup is a plain file copy of {DB_FILE} taken while holding the DB
/// mutex, so no write from this process lands in the file mid-copy. It is a
/// cheap best-effort snapshot (not a proper SQLite online backup); restore
/// quality is "last consistent moment", which is the accepted trade-off for
/// not shipping a second tool.
async fn maintenance_loop(state: Arc<AppState>) {
    let mut retention = tokio::time::interval(RETENTION_INTERVAL);
    retention.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut backup = tokio::time::interval(BACKUP_INTERVAL);
    backup.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tokio::select! {
            _ = retention.tick() => {
                match state.db.lock() {
                    Ok(conn) => match db::prune_old_data(&conn) {
                        Ok((jobs, convs)) => eprintln!(
                            "retention: removed {jobs} job(s) and {convs} conversation(s) older than 30 days"
                        ),
                        Err(e) => eprintln!("retention failed: {e}"),
                    },
                    Err(_) => eprintln!("retention failed: database mutex poisoned"),
                }
            }
            _ = backup.tick() => {
                if backup_is_stale() {
                    // Hold the DB mutex across the copy: the guard is dropped
                    // at the end of this block, never held across an await.
                    match state.db.lock() {
                        Ok(_conn) => match std::fs::copy(DB_FILE, DB_BACKUP_FILE) {
                            Ok(bytes) => eprintln!(
                                "backup: copied {DB_FILE} -> {DB_BACKUP_FILE} ({bytes} bytes)"
                            ),
                            Err(e) => eprintln!("backup failed: {e}"),
                        },
                        Err(_) => eprintln!("backup failed: database mutex poisoned"),
                    }
                }
            }
        }
    }
}

#[tokio::main]
async fn main() {
    // DB file next to the working directory; bootstrap failures abort.
    let conn = Connection::open(DB_FILE)
        .unwrap_or_else(|e| panic!("cannot open {DB_FILE}: {e}"));
    db::init(&conn).unwrap_or_else(|e| panic!("cannot init schema: {e}"));

    // Startup validation via ai::validate_outbound_url (inside from_env):
    // invalid config only disables the bot, the server still runs.
    let ai = AiConfig::from_env();
    if ai.is_configured() {
        eprintln!("AI proxy enabled: endpoint={} model={}", ai.url, ai.model);
    } else {
        eprintln!("AI bot disabled: {}", ai.reason);
    }

    let admin_user =
        std::env::var("DESKAGENT_ADMIN_USER").unwrap_or_else(|_| "admin".to_string());
    let (admin_pass, pass_generated) = match std::env::var("DESKAGENT_ADMIN_PASS") {
        Ok(pass) if !pass.trim().is_empty() => (pass, false),
        _ => {
            use ring::rand::{SecureRandom, SystemRandom};
            let rng = SystemRandom::new();
            let mut bytes = [0u8; 16];
            rng.fill(&mut bytes).expect("CSPRNG failure");
            let pass: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            (pass, true)
        }
    };
    if pass_generated {
        // The generated password must never go to stderr/log (logs are
        // collected and archived). It is written to a local file instead and
        // that file is deleted after the first successful admin login.
        match std::fs::write(BOOTSTRAP_PASS_FILE, format!("{}\n", admin_pass)) {
            Ok(()) => eprintln!(
                "CẢNH BÁO BẢO MẬT / SECURITY WARNING: DESKAGENT_ADMIN_PASS không được cấu hình. \
                 Đã sinh mật khẩu ngẫu nhiên và ghi vào file '{}' (tự xóa sau lần đăng nhập admin \
                 đầu tiên; hãy đặt DESKAGENT_ADMIN_PASS cho production).",
                BOOTSTRAP_PASS_FILE
            ),
            Err(e) => eprintln!(
                "LỖI: không thể ghi mật khẩu admin sinh tự động vào '{}': {} \
                 (đặt DESKAGENT_ADMIN_PASS để đăng nhập)",
                BOOTSTRAP_PASS_FILE, e
            ),
        }
    } else if admin_pass == "deskagent" || admin_pass == "admin" || admin_pass.len() < 8 {
        // Fail-closed: a guessable admin password protects the deploy-job
        // console (RCE-grade power), so weak values are refused, not warned.
        panic!(
            "DESKAGENT_ADMIN_PASS quá yếu (\"deskagent\"/\"admin\"/dưới 8 ký tự không được chấp \
             nhận). Hãy đặt mật khẩu phức tạp hơn qua biến môi trường DESKAGENT_ADMIN_PASS."
        );
    }
    eprintln!("admin auth configured: user={}", admin_user);

    // Deploy job signing key: env var wins; otherwise a random seed is
    // generated once and persisted. The historical hardcoded fallback key is
    // gone — anyone with the source could forge jobs accepted by clients
    // built with the matching default pubkey.
    const PRIVKEY_FILE: &str = "manager_privkey.seed";
    let server_privkey = match std::env::var("DESKAGENT_SERVER_PRIVKEY") {
        Ok(k) if !k.trim().is_empty() => k.trim().to_string(),
        _ => match std::fs::read_to_string(PRIVKEY_FILE) {
            Ok(existing) if !existing.trim().is_empty() => existing.trim().to_string(),
            _ => {
                let generated = crypto::generate_private_key()
                    .unwrap_or_else(|e| panic!("cannot generate server signing key: {e}"));
                if let Err(e) = std::fs::write(PRIVKEY_FILE, format!("{}\n", generated)) {
                    panic!("cannot persist the generated signing key to {PRIVKEY_FILE}: {e}");
                }
                eprintln!(
                    "CẢNH BÁO BẢO MẬT: DESKAGENT_SERVER_PRIVKEY không được cấu hình. \
                     Đã sinh cặp khóa ký deploy job ngẫu nhiên và lưu seed vào file '{}' \
                     (hãy cấu hình biến môi trường DESKAGENT_SERVER_PRIVKEY cho production).",
                    PRIVKEY_FILE
                );
                generated
            }
        },
    };

    if let Err(e) = crypto::sign_deploy_payload(&server_privkey, "init", "init", "", "", "init") {
        panic!("DESKAGENT_SERVER_PRIVKEY không hợp lệ: {e}");
    }
    // Publish the matching public key to the client config if not configured.
    // Both anchors are published: `server_key` (rendezvous) and the separate
    // `deploy_pubkey` (deploy-signing trust anchor) so rotating one never
    // silently swaps the other.
    match crypto::derive_public_key(&server_privkey) {
        Ok(pub_b64) => {
            if let Err(e) = db::set_setting_if_empty(&conn, "server_key", &pub_b64) {
                eprintln!("cannot persist the derived server key: {e}");
            }
            if let Err(e) = db::set_setting_if_empty(&conn, "deploy_pubkey", &pub_b64) {
                eprintln!("cannot persist the derived deploy pubkey: {e}");
            }
        }
        Err(e) => eprintln!("cannot derive the server public key: {e}"),
    }

    // Legacy shared-token escape hatch for fleet migration. Per-device auth
    // (X-Device-Token, minted at register) is the default and is FAIL-CLOSED:
    // without a valid token, /api/client/* and /api/conversations/* reject.
    let client_token = std::env::var("DESKAGENT_CLIENT_TOKEN")
        .map(|t| t.trim().to_string())
        .unwrap_or_default();
    if client_token.is_empty() {
        eprintln!(
            "Client API auth: per-device tokens (X-Device-Token) are REQUIRED. \
             DESKAGENT_CLIENT_TOKEN (legacy shared-token override) is not set."
        );
    }

    let state = Arc::new(AppState {
        db: Mutex::new(conn),
        ai,
        admin_user,
        admin_pass,
        server_privkey,
        client_token,
    });

    // Background maintenance: data retention + cheap DB backup.
    tokio::spawn(maintenance_loop(state.clone()));

    let bind =
        std::env::var("DESKAGENT_MANAGER_BIND").unwrap_or_else(|_| "0.0.0.0:8080".to_string());
    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .unwrap_or_else(|e| panic!("cannot bind {bind}: {e}"));
    eprintln!("deskagent-manager listening on http://{bind}");
    if !bind.starts_with("127.0.0.1") && !bind.starts_with("localhost") && !bind.starts_with("[::1]") {
        eprintln!(
            "CẢNH BẢO BẢO MẬT / SECURITY WARNING: Manager đang chạy HTTP thuần trên {} — \
             mật khẩu admin và token được truyền trên dây dạng cleartext. \
             Hãy đặt phía sau một reverse proxy TLS (hoặc VPN) trong production.",
            bind
        );
    }

    axum::serve(
        listener,
        routes::router(state).into_make_service_with_connect_info::<std::net::SocketAddr>(),
    )
    .await
    .unwrap_or_else(|e| panic!("server error: {e}"));
}

// Shared SQLite access for the control plane.
//
// The control plane opens the SAME database file as deskagent-manager
// (DESKAGENT_CONTROL_DB, default "manager.db" in the shared /data volume)
// and reuses its auth tables with byte-identical schemes:
//
// - admin_tokens(token = base64(SHA-256), created_at): manager console login
//   mints these (manager routes::login); invite issuance requires one.
// - device_tokens(token_hash, client_id, created_at): per-device identity,
//   minted once, never re-issued — same as manager register_client.
// - clients(id, ...): ONE identity namespace; the v2 peer_id IS the DeskAgent
//   client id, so enrollment upserts the same row manager serves.
// - settings(key, value): the server trust anchor lives here
//   (settings.server_key, published by manager from DESKAGENT_SERVER_PRIVKEY).
//
// New tables owned by this service:
// - enroll_invites(code_hash, created_at, used_at): single-use enrollment
//   invite codes. Only hashes at rest; plaintext shown once at issuance.
//
// Multi-process contract: both services use short transactions and never hold
// the connection mutex across .await. This service sets WAL + busy_timeout on
// ITS OWN connections (a persistent DB property, safe to enable from here);
// manager keeps its own open flags. SQLite file locking serializes writers.

use rusqlite::{params, Connection, OptionalExtension};
use std::time::{SystemTime, UNIX_EPOCH};

/// Invite lifetime: single use, expires after 24h if unclaimed.
pub const INVITE_TTL_SECS: i64 = 86400;

/// Mirror of manager db.rs ADMIN_TOKEN_TTL_SECS (7 days): admin bearer tokens
/// older than this are treated as expired (and pruned on sight, like manager).
pub const ADMIN_TOKEN_TTL_SECS: i64 = 604800;

/// Tables this service owns. Shared tables are created IF NOT EXISTS with the
/// same definitions as manager/src/db.rs so a fresh volume works when this
/// service starts before manager; on an existing volume this is a no-op.
const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS clients (
    id TEXT PRIMARY KEY,
    hostname TEXT NOT NULL DEFAULT '',
    os TEXT NOT NULL DEFAULT '',
    os_version TEXT NOT NULL DEFAULT '',
    arch TEXT NOT NULL DEFAULT '',
    ip TEXT NOT NULL DEFAULT '',
    version TEXT NOT NULL DEFAULT '',
    last_seen INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS admin_tokens (
    token TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS device_tokens (
    token_hash TEXT PRIMARY KEY,
    client_id TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS enroll_invites (
    code_hash TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL DEFAULT 0,
    used_at INTEGER
);
";

pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Open the shared DB: WAL for multi-process readers/writers + busy wait
/// instead of instant SQLITE_BUSY, then ensure our tables exist.
pub fn open(path: &str) -> rusqlite::Result<Connection> {
    let conn = Connection::open(path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;")?;
    conn.execute_batch(SCHEMA)?;
    Ok(conn)
}

// ---------- admin tokens (read/verify only; minted by manager console) ----------

/// True when the bearer token's hash is a live (unexpired) admin token.
/// Expired rows are pruned on sight, mirroring manager behavior.
pub fn check_admin_token(conn: &Connection, token: &str) -> rusqlite::Result<bool> {
    let created: Option<i64> = conn
        .query_row(
            "SELECT created_at FROM admin_tokens WHERE token = ?1",
            params![crate::auth::hash_token(token)],
            |row| row.get(0),
        )
        .optional()?;
    match created {
        Some(t) => {
            let age = now() - t;
            if age > ADMIN_TOKEN_TTL_SECS || age < 0 {
                let _ = conn.execute(
                    "DELETE FROM admin_tokens WHERE token = ?1",
                    params![crate::auth::hash_token(token)],
                );
                Ok(false)
            } else {
                Ok(true)
            }
        }
        None => Ok(false),
    }
}

// ---------- device tokens ----------

pub fn create_device_token(
    conn: &Connection,
    token_hash: &str,
    client_id: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO device_tokens (token_hash, client_id, created_at) VALUES (?1, ?2, ?3)",
        params![token_hash, client_id, now()],
    )?;
    Ok(())
}

/// True when a client row with this id already exists.
/// (Kept for the punch-path authorization follow-up: relays currently attach
/// by session UUID; peer-gated allocation will call this.)
#[allow(dead_code)]
pub fn client_exists(conn: &Connection, id: &str) -> rusqlite::Result<bool> {
    let n: i64 = conn.query_row(
        "SELECT COUNT(*) FROM clients WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )?;
    Ok(n > 0)
}

/// Insert the client row if missing (enrollment path); never overwrites an
/// existing row's identity. Returns true when the row was created.
pub fn ensure_client(
    conn: &Connection,
    id: &str,
    hostname: &str,
    os: &str,
    ed25519_pubkey_b64: &str,
) -> rusqlite::Result<bool> {
    let _ = ed25519_pubkey_b64;
    let n = conn.execute(
        "INSERT OR IGNORE INTO clients (id, hostname, os, last_seen, created_at) VALUES (?1, ?2, ?3, ?4, ?4)",
        params![id, hostname, os, now()],
    )?;
    Ok(n == 1)
}

pub fn get_setting(conn: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT value FROM settings WHERE key = ?1",
        params![key],
        |row| row.get(0),
    )
    .optional()
}

// ---------- enrollment invites (single-use) ----------

pub fn create_invite(conn: &Connection, code_hash: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO enroll_invites (code_hash, created_at, used_at) VALUES (?1, ?2, NULL)",
        params![code_hash, now()],
    )?;
    Ok(())
}

/// Atomically consume an invite: succeeds only when the code exists, is unused
/// and is within TTL. Returns false when the invite is unknown/used/expired
/// (indistinguishable on purpose).
pub fn consume_invite(conn: &Connection, code_hash: &str) -> rusqlite::Result<bool> {
    let n = conn.execute(
        "UPDATE enroll_invites SET used_at = ?1 WHERE code_hash = ?2 AND used_at IS NULL AND created_at > ?3",
        params![now(), code_hash, now() - INVITE_TTL_SECS],
    )?;
    Ok(n == 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn memdb() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(SCHEMA).unwrap();
        conn
    }

    #[test]
    fn invite_single_use_and_expiry() {
        let conn = memdb();
        create_invite(&conn, "h1").unwrap();
        assert!(consume_invite(&conn, "h1").unwrap());
        // Second consume fails: already used.
        assert!(!consume_invite(&conn, "h1").unwrap());
        // Unknown code fails.
        assert!(!consume_invite(&conn, "nope").unwrap());
        // Expired invite fails.
        conn.execute(
            "INSERT INTO enroll_invites (code_hash, created_at, used_at) VALUES ('h2', ?1, NULL)",
            params![now() - INVITE_TTL_SECS - 10],
        )
        .unwrap();
        assert!(!consume_invite(&conn, "h2").unwrap());
    }

    #[test]
    fn ensure_client_never_overwrites() {
        let conn = memdb();
        assert!(ensure_client(&conn, "c1", "h1", "win", "pk").unwrap());
        assert!(!ensure_client(&conn, "c1", "evil", "evil", "evil").unwrap());
        let host: String = conn
            .query_row("SELECT hostname FROM clients WHERE id='c1'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(host, "h1");
    }
}

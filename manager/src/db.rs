// SQLite storage for the manager: schema + every query.
// All statements use prepare + positional parameters (params!) — SQL is never
// built by string formatting/concatenation. Times are unix epoch seconds.

use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use std::time::{SystemTime, UNIX_EPOCH};

/// Keep at most this many newest events per client.
const MAX_EVENTS_PER_CLIENT: i64 = 500;

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
CREATE TABLE IF NOT EXISTS inventory (
    client_id TEXT PRIMARY KEY,
    json TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT '',
    text TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL DEFAULT '',
    package_url TEXT,
    package_path TEXT,
    silent_cmd TEXT NOT NULL DEFAULT '',
    signature TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS job_results (
    job_id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT '',
    output TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    client_id TEXT,
    claimed INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'open',
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id TEXT NOT NULL DEFAULT '',
    sender TEXT NOT NULL DEFAULT '',
    text TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS admin_tokens (
    token TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS device_tokens (
    token_hash TEXT PRIMARY KEY,
    client_id TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
);
";

/// Current unix epoch seconds.
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Create all tables if missing.
pub fn init(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(SCHEMA)?;
    let _ = conn.execute("ALTER TABLE jobs ADD COLUMN signature TEXT NOT NULL DEFAULT ''", []);
    let _ = conn.execute("ALTER TABLE clients ADD COLUMN ip TEXT NOT NULL DEFAULT ''", []);
    // Client app build version (reported at register; empty for old clients).
    let _ = conn.execute("ALTER TABLE clients ADD COLUMN version TEXT NOT NULL DEFAULT ''", []);
    // Job delivery lease: NULL on old rows means "expired", so jobs stuck in
    // 'running' by older builds become claimable again.
    let _ = conn.execute("ALTER TABLE jobs ADD COLUMN lease_expires_at INTEGER", []);
    // Stable per-machine identity (Windows MachineGuid): lets register collapse
    // the per-user-context duplicate rows one machine used to accumulate.
    let _ = conn.execute("ALTER TABLE clients ADD COLUMN machine_id TEXT NOT NULL DEFAULT ''", []);
    migrate_admin_token_hashes(conn)?;
    Ok(())
}

// ---------- admin tokens ----------
//
// Only the SHA-256 hash of the token is stored (same scheme as device
// tokens): a DB leak must not yield usable admin credentials.

pub const ADMIN_TOKEN_TTL_SECS: i64 = 604800; // 7 days

pub fn create_admin_token(conn: &Connection, token: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO admin_tokens (token, created_at) VALUES (?1, ?2)",
        params![crate::crypto::hash_token(token), now()],
    )?;
    Ok(())
}

pub fn check_admin_token(conn: &Connection, token: &str) -> rusqlite::Result<bool> {
    let mut stmt = conn.prepare("SELECT created_at FROM admin_tokens WHERE token = ?1")?;
    let created_at: Option<i64> = stmt
        .query_row(params![crate::crypto::hash_token(token)], |row| row.get(0))
        .optional()?;
    match created_at {
        Some(created) => {
            let age = now() - created;
            if age > ADMIN_TOKEN_TTL_SECS || age < 0 {
                delete_admin_token(conn, token)?;
                Ok(false)
            } else {
                Ok(true)
            }
        }
        None => Ok(false),
    }
}

pub fn delete_admin_token(conn: &Connection, token: &str) -> rusqlite::Result<()> {
    conn.execute(
        "DELETE FROM admin_tokens WHERE token = ?1",
        params![crate::crypto::hash_token(token)],
    )?;
    Ok(())
}

/// One-time migration: admin tokens stored as plaintext (from builds that
/// predate hashing) are hashed in place so existing bearer tokens keep
/// working. A stored hash is base64(SHA-256) — always 44 chars ending '=';
/// minted plaintext tokens are `tok_` + 32 hex (36 chars), so anything that
/// does not look like a base64 digest is re-hashed exactly once.
fn migrate_admin_token_hashes(conn: &Connection) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare("SELECT token FROM admin_tokens")?;
    let rows: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))?
        .filter_map(Result::ok)
        .collect();
    for token in rows {
        if token.len() == 44 && token.ends_with('=') {
            continue; // already a stored hash
        }
        conn.execute(
            "UPDATE admin_tokens SET token = ?2 WHERE token = ?1",
            params![token, crate::crypto::hash_token(&token)],
        )?;
    }
    Ok(())
}

// ---------- device tokens (per-client identity) ----------
//
// Only the SHA-256 hash of the token is stored: a DB leak must not yield
// usable credentials. Tokens are minted once at register and never re-issued
// for an existing client id.

pub fn create_device_token(conn: &Connection, token_hash: &str, client_id: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO device_tokens (token_hash, client_id, created_at) VALUES (?1, ?2, ?3)",
        params![token_hash, client_id, now()],
    )?;
    Ok(())
}

/// Client id bound to a device-token hash, if the hash is known.
pub fn device_client_id(conn: &Connection, token_hash: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT client_id FROM device_tokens WHERE token_hash = ?1",
        params![token_hash],
        |row| row.get(0),
    )
    .optional()
}

/// True when a client row with this id already exists (register must not
/// re-mint tokens for known ids without presenting a valid token).
pub fn client_exists(conn: &Connection, id: &str) -> rusqlite::Result<bool> {
    let n: i64 = conn.query_row(
        "SELECT COUNT(*) FROM clients WHERE id = ?1",
        params![id],
        |row| row.get(0),
    )?;
    Ok(n > 0)
}

// ---------- settings ----------

pub fn get_setting(conn: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    let mut stmt = conn.prepare("SELECT value FROM settings WHERE key = ?1")?;
    let val = stmt.query_row(params![key], |row| row.get(0)).optional()?;
    Ok(val)
}

pub fn set_setting(conn: &Connection, key: &str, value: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        params![key, value, now()],
    )?;
    Ok(())
}

/// Set a setting only when it is not present yet (keeps admin-configured values).
pub fn set_setting_if_empty(conn: &Connection, key: &str, value: &str) -> rusqlite::Result<()> {
    if get_setting(conn, key)?.map(|v| v.trim().is_empty()).unwrap_or(true) {
        set_setting(conn, key, value)?;
    }
    Ok(())
}

pub fn get_all_settings(conn: &Connection) -> rusqlite::Result<std::collections::HashMap<String, String>> {
    let mut stmt = conn.prepare("SELECT key, value FROM settings")?;
    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    let mut map = std::collections::HashMap::new();
    for r in rows {
        let (k, v) = r?;
        map.insert(k, v);
    }
    Ok(map)
}

pub fn get_effective_ai_config(conn: &Connection) -> rusqlite::Result<(String, String, String, String)> {
    let url = get_setting(conn, "ai_url")?.unwrap_or_default();
    let key = get_setting(conn, "ai_key")?.unwrap_or_default();
    let model = get_setting(conn, "ai_model")?.unwrap_or_default();
    let prompt = get_setting(conn, "ai_prompt")?.unwrap_or_default();

    let effective_url = if !url.is_empty() {
        url
    } else {
        std::env::var(crate::ai::ENV_URL).unwrap_or_default()
    };
    let effective_key = if !key.is_empty() {
        key
    } else {
        std::env::var(crate::ai::ENV_KEY).unwrap_or_default()
    };
    let effective_model = if !model.is_empty() {
        model
    } else {
        std::env::var(crate::ai::ENV_MODEL).unwrap_or_default()
    };

    Ok((effective_url, effective_key, effective_model, prompt))
}

// ---------- clients ----------

#[derive(Debug, Serialize, Clone)]
pub struct ClientRow {
    pub id: String,
    pub hostname: String,
    pub os: String,
    pub os_version: String,
    pub arch: String,
    pub ip: String,
    /// Client app build version, reported at register ("" for old clients
    /// that predate the field).
    pub version: String,
    pub last_seen: i64,
    pub created_at: i64,
}

/// Insert or refresh a client row (created_at keeps its original value).
///
/// `machine_id` is the stable per-machine identity (Windows MachineGuid); an
/// empty value keeps whatever the row already carries, so legacy clients that
/// do not send one never erase a previously learned identity.
pub fn upsert_client(
    conn: &Connection,
    id: &str,
    hostname: &str,
    os: &str,
    os_version: &str,
    arch: &str,
    ip: &str,
    version: &str,
    machine_id: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO clients (id, hostname, os, os_version, arch, ip, version, machine_id, last_seen, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
         ON CONFLICT(id) DO UPDATE SET
            hostname = excluded.hostname,
            os = excluded.os,
            os_version = excluded.os_version,
            arch = excluded.arch,
            ip = CASE WHEN excluded.ip != '' THEN excluded.ip ELSE clients.ip END,
            version = CASE WHEN excluded.version != '' THEN excluded.version ELSE clients.version END,
            machine_id = CASE WHEN excluded.machine_id != '' THEN excluded.machine_id ELSE clients.machine_id END,
            last_seen = excluded.last_seen",
        params![id, hostname, os, os_version, arch, ip, version, machine_id, now()],
    )?;
    Ok(())
}

/// The canonical client id for a machine: the most recent row already carrying
/// this machine_id.
///
/// [Note]
/// Hostname-only rows are deliberately NOT considered here: adopting one
/// without the row's own device token would let anyone who knows a hostname
/// mint a token for another machine's row (identity takeover). Legacy
/// hostname-only adoption is handled separately in `find_hostname_only_client`
/// under stricter conditions.
pub fn find_canonical_client(conn: &Connection, machine_id: &str) -> rusqlite::Result<Option<String>> {
    if machine_id.is_empty() {
        return Ok(None);
    }
    conn.query_row(
        "SELECT id FROM clients WHERE machine_id = ?1 ORDER BY last_seen DESC LIMIT 1",
        params![machine_id],
        |row| row.get::<_, String>(0),
    )
    .optional()
}

/// Newest row that still carries no machine_id for this hostname (a row
/// written before the machine_id column existed). Callers must verify it is
/// safe to adopt: the row has no device token (true legacy row) or the caller
/// presented the exact token bound to it.
///
/// An empty hostname never matches: otherwise the `hostname = ''` predicate
/// would coalesce unrelated machines that all fail to report a hostname into
/// one tokenless row.
pub fn find_hostname_only_client(conn: &Connection, hostname: &str) -> rusqlite::Result<Option<String>> {
    if hostname.is_empty() {
        return Ok(None);
    }
    conn.query_row(
        "SELECT id FROM clients WHERE hostname = ?1 AND machine_id = '' ORDER BY last_seen DESC LIMIT 1",
        params![hostname],
        |row| row.get::<_, String>(0),
    )
    .optional()
}

/// True when at least one device token is bound to this client row.
pub fn client_has_device_token(conn: &Connection, id: &str) -> rusqlite::Result<bool> {
    let n: i64 = conn.query_row(
        "SELECT COUNT(*) FROM device_tokens WHERE client_id = ?1",
        params![id],
        |row| row.get(0),
    )?;
    Ok(n > 0)
}

/// Stored machine_id of a client row; None when the row does not exist.
pub fn client_machine_id(conn: &Connection, id: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT machine_id FROM clients WHERE id = ?1",
        params![id],
        |row| row.get::<_, String>(0),
    )
    .optional()
}

/// Delete a client row together with everything that hangs off it.
pub fn delete_client_everything(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM device_tokens WHERE client_id = ?1", params![id])?;
    conn.execute("DELETE FROM inventory WHERE client_id = ?1", params![id])?;
    conn.execute("DELETE FROM events WHERE client_id = ?1", params![id])?;
    conn.execute(
        "DELETE FROM job_results WHERE job_id IN (SELECT id FROM jobs WHERE client_id = ?1)",
        params![id],
    )?;
    conn.execute("DELETE FROM jobs WHERE client_id = ?1", params![id])?;
    conn.execute("DELETE FROM clients WHERE id = ?1", params![id])?;
    Ok(())
}

/// Collapse duplicate rows of one machine into `keep_id`.
///
/// [Note]
/// A row is a duplicate ONLY when it carries the same machine_id — matching
/// MachineGuid read from the local machine is the hardware proof required to
/// merge. Hostname-only rows are NEVER deleted here: two different machines
/// can share a hostname, and a hostname match alone would delete someone
/// else's row (with its events, inventory and tokens).
pub fn delete_duplicate_clients(
    conn: &Connection,
    keep_id: &str,
    machine_id: &str,
) -> rusqlite::Result<usize> {
    if machine_id.is_empty() {
        return Ok(0);
    }
    let mut stmt = conn.prepare("SELECT id FROM clients WHERE id != ?1 AND machine_id = ?2")?;
    let victims: Vec<String> = stmt
        .query_map(params![keep_id, machine_id], |row| row.get(0))?
        .filter_map(Result::ok)
        .collect();
    let n = victims.len();
    for id in victims {
        delete_client_everything(conn, &id)?;
    }
    Ok(n)
}

/// Delete every client row whose last_seen is older than 30 days, together
/// with everything hanging off it (run at register to self-prune stale rows).
pub const CLIENT_STALE_SECS: i64 = 30 * 24 * 3600;

pub fn prune_stale_clients(conn: &Connection) -> rusqlite::Result<usize> {
    let cutoff = now() - CLIENT_STALE_SECS;
    let mut stmt = conn.prepare("SELECT id FROM clients WHERE last_seen < ?1")?;
    let stale: Vec<String> = stmt
        .query_map(params![cutoff], |row| row.get(0))?
        .filter_map(Result::ok)
        .collect();
    let n = stale.len();
    for id in stale {
        delete_client_everything(conn, &id)?;
    }
    Ok(n)
}

/// Retention: delete jobs (with their results) and conversations (with their
/// messages) older than 30 days. Returns (jobs removed, conversations removed).
pub const RETENTION_SECS: i64 = 30 * 24 * 3600;

pub fn prune_old_data(conn: &Connection) -> rusqlite::Result<(usize, usize)> {
    let cutoff = now() - RETENTION_SECS;
    conn.execute(
        "DELETE FROM job_results WHERE job_id IN (SELECT id FROM jobs WHERE created_at < ?1)",
        params![cutoff],
    )?;
    let jobs = conn.execute("DELETE FROM jobs WHERE created_at < ?1", params![cutoff])?;
    conn.execute(
        "DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE created_at < ?1)",
        params![cutoff],
    )?;
    let convs = conn.execute("DELETE FROM conversations WHERE created_at < ?1", params![cutoff])?;
    Ok((jobs, convs))
}

pub fn list_clients(conn: &Connection) -> rusqlite::Result<Vec<ClientRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, hostname, os, os_version, arch, ip, version, last_seen, created_at
         FROM clients ORDER BY last_seen DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(ClientRow {
            id: row.get(0)?,
            hostname: row.get(1)?,
            os: row.get(2)?,
            os_version: row.get(3)?,
            arch: row.get(4)?,
            ip: row.get(5)?,
            version: row.get(6)?,
            last_seen: row.get(7)?,
            created_at: row.get(8)?,
        })
    })?;
    rows.collect()
}

// ---------- inventory ----------

/// Store one inventory snapshot per client (upsert on client_id).
pub fn save_inventory(conn: &Connection, client_id: &str, json: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO inventory (client_id, json, updated_at) VALUES (?1, ?2, ?3)
         ON CONFLICT(client_id) DO UPDATE SET
            json = excluded.json,
            updated_at = excluded.updated_at",
        params![client_id, json, now()],
    )?;
    Ok(())
}

/// Stored inventory JSON text + update timestamp.
pub fn get_inventory(conn: &Connection, client_id: &str) -> rusqlite::Result<Option<(String, i64)>> {
    conn.query_row(
        "SELECT json, updated_at FROM inventory WHERE client_id = ?1",
        params![client_id],
        |row| Ok((row.get::<_, String>(0)?, row.get(1)?)),
    )
    .optional()
}

/// (id, machine_id) of the NEWEST client row with this hostname; ties and
/// stale duplicates resolve to the row the machine last touched.
pub fn find_client_by_hostname(conn: &Connection, hostname: &str) -> rusqlite::Result<Option<(String, String)>> {
    conn.query_row(
        "SELECT id, machine_id FROM clients WHERE LOWER(hostname) = LOWER(?1) OR id = ?1 OR ip = ?1 ORDER BY last_seen DESC LIMIT 1",
        params![hostname],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )
    .optional()
}

// ---------- events ----------

#[derive(Debug, Serialize)]
pub struct EventRow {
    pub id: i64,
    pub client_id: String,
    pub source: String,
    pub text: String,
    pub created_at: i64,
}

/// Batch insert events, then prune so each client keeps only the newest
/// MAX_EVENTS_PER_CLIENT rows.
pub fn insert_events(
    conn: &Connection,
    client_id: &str,
    events: &[(String, String, i64)],
) -> rusqlite::Result<()> {
    let tx = conn.unchecked_transaction()?;
    for (source, text, created_at) in events {
        tx.execute(
            "INSERT INTO events (client_id, source, text, created_at) VALUES (?1, ?2, ?3, ?4)",
            params![client_id, source, text, created_at],
        )?;
    }
    tx.execute(
        "DELETE FROM events WHERE client_id = ?1 AND id NOT IN (
            SELECT id FROM events WHERE client_id = ?1 ORDER BY id DESC LIMIT ?2
        )",
        params![client_id, MAX_EVENTS_PER_CLIENT],
    )?;
    tx.commit()
}

/// Newest events for a client, descending.
pub fn list_events(conn: &Connection, client_id: &str, limit: i64) -> rusqlite::Result<Vec<EventRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, source, text, created_at
         FROM events WHERE client_id = ?1 ORDER BY id DESC LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![client_id, limit], |row| {
        Ok(EventRow {
            id: row.get(0)?,
            client_id: client_id.to_string(),
            source: row.get(1)?,
            text: row.get(2)?,
            created_at: row.get(3)?,
        })
    })?;
    rows.collect()
}

// ---------- jobs ----------

/// One job as delivered to a client (`GET /api/client/:id/jobs`).
///
/// [Note]
/// `package_url`/`package_path` are non-optional strings on purpose: the
/// wire format must never contain JSON `null` for them. Older clients
/// deserialize them as `String` with `#[serde(default)]`, which only fills a
/// value when the field is MISSING — a serialized `null` fails their parse,
/// the job is never executed and its lease redelivery loops forever. Empty
/// string is the established "no package" encoding (the client treats "" as
/// absent in `run_job` and the signature payload is built the same way).
#[derive(Debug, Serialize)]
pub struct JobRow {
    pub id: String,
    pub client_id: String,
    pub package_url: String,
    pub package_path: String,
    pub silent_cmd: String,
    pub signature: String,
    pub status: String,
    pub created_at: i64,
}

#[derive(Debug, Serialize)]
pub struct JobResultRow {
    pub job_id: String,
    pub client_id: String,
    pub status: String,
    pub output: String,
    pub created_at: i64,
}

#[derive(Debug, Serialize)]
pub struct JobWithResult {
    pub id: String,
    pub client_id: String,
    pub package_url: Option<String>,
    pub package_path: Option<String>,
    pub silent_cmd: String,
    pub signature: String,
    pub status: String,
    pub created_at: i64,
    pub result: Option<JobResultRow>,
}

pub fn insert_job(
    conn: &Connection,
    id: &str,
    client_id: &str,
    package_url: Option<&str>,
    package_path: Option<&str>,
    silent_cmd: &str,
    signature: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO jobs (id, client_id, package_url, package_path, silent_cmd, signature, status, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'pending', ?7)",
        params![id, client_id, package_url, package_path, silent_cmd, signature, now()],
    )?;
    Ok(())
}

fn job_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<JobRow> {
    Ok(JobRow {
        id: row.get(0)?,
        client_id: row.get(1)?,
        // NULL columns (cmd-only jobs) serialize as "" on the wire, never null.
        package_url: row.get::<_, Option<String>>(2)?.unwrap_or_default(),
        package_path: row.get::<_, Option<String>>(3)?.unwrap_or_default(),
        silent_cmd: row.get(4)?,
        signature: row.get(5)?,
        status: row.get(6)?,
        created_at: row.get(7)?,
    })
}

/// Jobs deliverable to a client: never-claimed jobs plus jobs whose delivery
/// lease has expired (the claiming response may have been lost on plain HTTP
/// or the client died before running the job — a lease expiry returns the job
/// to the pool instead of leaving it stuck in 'running' forever).
pub fn claimable_jobs(conn: &Connection, client_id: &str, now: i64) -> rusqlite::Result<Vec<JobRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, client_id, package_url, package_path, silent_cmd, signature, status, created_at
         FROM jobs
         WHERE client_id = ?1
           AND (status = 'pending'
                OR (status = 'running' AND (lease_expires_at IS NULL OR lease_expires_at < ?2)))
         ORDER BY created_at ASC",
    )?;
    let rows = stmt.query_map(params![client_id, now], job_from_row)?;
    rows.collect()
}

/// Claim a job for delivery: mark it running with a fresh lease deadline.
pub fn claim_job(conn: &Connection, job_id: &str, lease_expires_at: i64) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE jobs SET status = 'running', lease_expires_at = ?2 WHERE id = ?1",
        params![job_id, lease_expires_at],
    )?;
    Ok(())
}

/// True when the job exists and belongs to the given client.
pub fn job_owned_by(conn: &Connection, job_id: &str, client_id: &str) -> rusqlite::Result<bool> {
    let n: i64 = conn.query_row(
        "SELECT COUNT(*) FROM jobs WHERE id = ?1 AND client_id = ?2",
        params![job_id, client_id],
        |row| row.get(0),
    )?;
    Ok(n > 0)
}

/// Refresh a client's last_seen without inserting or changing any other field
/// (liveness heartbeat; does not fabricate rows for unknown ids).
pub fn touch_client(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE clients SET last_seen = ?2 WHERE id = ?1",
        params![id, now()],
    )?;
    Ok(())
}

/// Store the client's result and advance the job to the reported status.
///
/// [Note]
/// The jobs row is only updated when it belongs to `client_id`, so a result
/// for a foreign/unknown job id can never rewrite another client's job state.
pub fn save_job_result(
    conn: &Connection,
    job_id: &str,
    client_id: &str,
    status: &str,
    output: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO job_results (job_id, client_id, status, output, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(job_id) DO UPDATE SET
            status = excluded.status,
            output = excluded.output,
            created_at = excluded.created_at",
        params![job_id, client_id, status, output, now()],
    )?;
    conn.execute(
        "UPDATE jobs SET status = ?2 WHERE id = ?1 AND client_id = ?3",
        params![job_id, status, client_id],
    )?;
    Ok(())
}

/// All jobs with their results (if any), newest first.
pub fn list_jobs(conn: &Connection) -> rusqlite::Result<Vec<JobWithResult>> {
    let mut stmt = conn.prepare(
        "SELECT j.id, j.client_id, j.package_url, j.package_path, j.silent_cmd, j.signature, j.status, j.created_at,
                r.status, r.output, r.created_at
         FROM jobs j
         LEFT JOIN job_results r ON r.job_id = j.id
         ORDER BY j.created_at DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        let result = match row.get::<_, Option<String>>(8)? {
            None => None,
            Some(status) => Some(JobResultRow {
                job_id: row.get::<_, String>(0)?,
                client_id: row.get::<_, String>(1)?,
                status,
                output: row.get::<_, Option<String>>(9)?.unwrap_or_default(),
                created_at: row.get::<_, Option<i64>>(10)?.unwrap_or(0),
            }),
        };
        Ok(JobWithResult {
            id: row.get(0)?,
            client_id: row.get(1)?,
            package_url: row.get(2)?,
            package_path: row.get(3)?,
            silent_cmd: row.get(4)?,
            signature: row.get(5)?,
            status: row.get(6)?,
            created_at: row.get(7)?,
            result,
        })
    })?;
    rows.collect()
}

// ---------- conversations ----------

#[derive(Debug, Serialize)]
pub struct ConversationRow {
    pub id: String,
    pub client_id: Option<String>,
    pub claimed: bool,
    pub status: String,
    pub created_at: i64,
}

pub fn insert_conversation(conn: &Connection, id: &str, client_id: Option<&str>) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO conversations (id, client_id, claimed, status, created_at)
         VALUES (?1, ?2, 0, 'open', ?3)",
        params![id, client_id, now()],
    )?;
    Ok(())
}

pub fn conversation_exists(conn: &Connection, id: &str) -> rusqlite::Result<bool> {
    conn.query_row("SELECT 1 FROM conversations WHERE id = ?1", params![id], |_| Ok(()))
        .optional()
        .map(|opt| opt.is_some())
}

/// Client id bound to a conversation, if any (used to enrich the AI context
/// with that machine's inventory and events).
pub fn conversation_client_id(conn: &Connection, id: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT client_id FROM conversations WHERE id = ?1",
        params![id],
        |row| row.get::<_, Option<String>>(0),
    )
    .optional()
    .map(|opt| opt.flatten())
}

pub fn is_conversation_claimed(conn: &Connection, id: &str) -> rusqlite::Result<bool> {
    let claimed: Option<i64> = conn
        .query_row("SELECT claimed FROM conversations WHERE id = ?1", params![id], |row| row.get(0))
        .optional()?;
    Ok(claimed.unwrap_or(0) != 0)
}

/// Admin takes over: the bot stops answering this conversation.
pub fn set_conversation_claimed(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    conn.execute("UPDATE conversations SET claimed = 1 WHERE id = ?1", params![id])?;
    Ok(())
}

pub fn set_conversation_closed(conn: &Connection, id: &str) -> rusqlite::Result<()> {
    conn.execute("UPDATE conversations SET status = 'closed' WHERE id = ?1", params![id])?;
    Ok(())
}

pub fn list_conversations(conn: &Connection) -> rusqlite::Result<Vec<ConversationRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, client_id, claimed, status, created_at FROM conversations ORDER BY created_at DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(ConversationRow {
            id: row.get(0)?,
            client_id: row.get(1)?,
            claimed: row.get::<_, i64>(2)? != 0,
            status: row.get(3)?,
            created_at: row.get(4)?,
        })
    })?;
    rows.collect()
}

// ---------- messages ----------

#[derive(Debug, Serialize)]
pub struct MessageRow {
    pub id: i64,
    pub sender: String,
    pub text: String,
    pub created_at: i64,
}

pub fn insert_message(conn: &Connection, conversation_id: &str, sender: &str, text: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO messages (conversation_id, sender, text, created_at) VALUES (?1, ?2, ?3, ?4)",
        params![conversation_id, sender, text, now()],
    )?;
    Ok(())
}

/// Messages with id > after, ascending (the Flutter client polls this).
pub fn messages_after(conn: &Connection, conversation_id: &str, after: i64) -> rusqlite::Result<Vec<MessageRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, sender, text, created_at
         FROM messages WHERE conversation_id = ?1 AND id > ?2 ORDER BY id ASC",
    )?;
    let rows = stmt.query_map(params![conversation_id, after], |row| {
        Ok(MessageRow {
            id: row.get(0)?,
            sender: row.get(1)?,
            text: row.get(2)?,
            created_at: row.get(3)?,
        })
    })?;
    rows.collect()
}

/// Last `cap` messages as (role, content) pairs for the model context:
/// "user" stays "user", bot/admin replies become "assistant".
pub fn ai_history(conn: &Connection, conversation_id: &str, cap: i64) -> rusqlite::Result<Vec<(String, String)>> {
    let mut stmt = conn.prepare(
        "SELECT sender, text FROM messages WHERE conversation_id = ?1 ORDER BY id DESC LIMIT ?2",
    )?;
    let mut pairs: Vec<(String, String)> = stmt
        .query_map(params![conversation_id, cap], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<Result<_, _>>()?;
    pairs.reverse();
    Ok(pairs
        .into_iter()
        .map(|(sender, text)| {
            let role = if sender == "user" { "user" } else { "assistant" };
            (role.to_string(), text)
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn admin_token_ttl_check() {
        let conn = Connection::open_in_memory().unwrap();
        init(&conn).unwrap();

        // Valid token created now (stored as SHA-256 hash, checked by value)
        let token_valid = "valid_tok";
        create_admin_token(&conn, token_valid).unwrap();
        assert!(check_admin_token(&conn, token_valid).unwrap());
        // Only the hash is at rest: a DB leak must not yield the token.
        let any_hashed: bool = {
            let mut stmt = conn.prepare("SELECT token FROM admin_tokens").unwrap();
            let all: Vec<String> = stmt
                .query_map([], |r| r.get(0))
                .unwrap()
                .filter_map(Result::ok)
                .collect();
            all.iter().any(|t| t == &crate::crypto::hash_token(token_valid))
        };
        assert!(any_hashed, "token stored hashed");

        // Expired token (created 8 days ago), inserted as a hash like prod code
        let token_expired = "expired_tok";
        let eight_days_ago = now() - (ADMIN_TOKEN_TTL_SECS + 86400);
        conn.execute(
            "INSERT INTO admin_tokens (token, created_at) VALUES (?1, ?2)",
            params![crate::crypto::hash_token(token_expired), eight_days_ago],
        )
        .unwrap();

        // Check should reject and delete expired token
        assert!(!check_admin_token(&conn, token_expired).unwrap());

        // Verify token is deleted from DB
        let mut stmt = conn.prepare("SELECT 1 FROM admin_tokens WHERE token = ?1").unwrap();
        let exists = stmt
            .query_row(params![crate::crypto::hash_token(token_expired)], |_| Ok(true))
            .optional()
            .unwrap()
            .unwrap_or(false);
        assert!(!exists);

        // Nonexistent token
        assert!(!check_admin_token(&conn, "nonexistent").unwrap());
    }

    #[test]
    fn admin_token_plaintext_migration_keeps_tokens_usable() {
        let conn = Connection::open_in_memory().unwrap();
        // Row written by an older build: plaintext token at rest.
        conn.execute_batch(SCHEMA).unwrap();
        conn.execute(
            "INSERT INTO admin_tokens (token, created_at) VALUES (?1, ?2)",
            params!["tok_plaintext123", now()],
        )
        .unwrap();

        init(&conn).unwrap(); // runs the one-time migration

        // The plaintext row was hashed in place and still authenticates.
        assert!(check_admin_token(&conn, "tok_plaintext123").unwrap());
        let mut stmt = conn.prepare("SELECT token FROM admin_tokens").unwrap();
        let all: Vec<String> = stmt
            .query_map([], |r| r.get(0))
            .unwrap()
            .filter_map(Result::ok)
            .collect();
        assert_eq!(all, vec![crate::crypto::hash_token("tok_plaintext123")]);
    }

    #[test]
    fn duplicate_collapse_never_touches_hostname_only_rows() {
        let conn = Connection::open_in_memory().unwrap();
        init(&conn).unwrap();
        upsert_client(&conn, "keep", "host-a", "Windows", "11", "x86_64", "1.2.3.4", "1.0", "M1").unwrap();
        // Different machine that happens to share the hostname, no machine_id.
        upsert_client(&conn, "other", "host-a", "Windows", "10", "x86_64", "1.2.3.5", "1.0", "").unwrap();
        create_device_token(&conn, &crate::crypto::hash_token("tok"), "other").unwrap();

        let removed = delete_duplicate_clients(&conn, "keep", "M1").unwrap();
        assert_eq!(removed, 0, "hostname-only rows are never collapsed");
        assert!(client_exists(&conn, "other").unwrap());
        assert!(client_has_device_token(&conn, "other").unwrap());

        // Same machine_id IS a duplicate and gets collapsed.
        upsert_client(&conn, "dup", "host-a", "Windows", "11", "x86_64", "1.2.3.6", "1.0", "M1").unwrap();
        let removed = delete_duplicate_clients(&conn, "keep", "M1").unwrap();
        assert_eq!(removed, 1);
        assert!(!client_exists(&conn, "dup").unwrap());
        assert!(client_exists(&conn, "other").unwrap());
    }

    #[test]
    fn hostname_only_adoption_requires_tokenless_row() {
        let conn = Connection::open_in_memory().unwrap();
        init(&conn).unwrap();
        upsert_client(&conn, "legacy", "host-l", "Windows", "10", "x86_64", "", "", "").unwrap();
        assert_eq!(
            find_hostname_only_client(&conn, "host-l").unwrap().as_deref(),
            Some("legacy")
        );
        assert!(!client_has_device_token(&conn, "legacy").unwrap(), "true legacy row");

        // A hostname-only row WITH a device token must not be adoptable via
        // hostname alone.
        upsert_client(&conn, "claimed", "host-c", "Windows", "10", "x86_64", "", "", "").unwrap();
        create_device_token(&conn, &crate::crypto::hash_token("tok-c"), "claimed").unwrap();
        assert!(client_has_device_token(&conn, "claimed").unwrap());

        // An empty hostname never matches, even when a tokenless row with a
        // blank hostname exists: unrelated machines that fail to report a
        // hostname must not be coalesced into one row.
        upsert_client(&conn, "blank-host", "", "Windows", "10", "x86_64", "", "", "").unwrap();
        assert_eq!(
            find_hostname_only_client(&conn, "").unwrap().as_deref(),
            None
        );

        assert_eq!(client_machine_id(&conn, "legacy").unwrap().as_deref(), Some(""));
        assert_eq!(client_machine_id(&conn, "missing").unwrap(), None);
    }

    #[test]
    fn prune_stale_clients_and_old_data_respect_cutoffs() {
        let conn = Connection::open_in_memory().unwrap();
        init(&conn).unwrap();
        let old = now() - (CLIENT_STALE_SECS + 3600);
        upsert_client(&conn, "stale", "h", "W", "10", "x86_64", "", "", "M").unwrap();
        conn.execute("UPDATE clients SET last_seen = ?1 WHERE id = 'stale'", params![old]).unwrap();
        upsert_client(&conn, "fresh", "h", "W", "10", "x86_64", "", "", "M").unwrap();

        // An old job owned by the FRESH client (stale clients are removed
        // wholesale by prune_stale_clients, jobs included).
        insert_job(&conn, "job-old", "fresh", None, None, "cmd", "sig").unwrap();
        conn.execute("UPDATE jobs SET created_at = ?1 WHERE id = 'job-old'", params![old]).unwrap();
        save_job_result(&conn, "job-old", "fresh", "success", "out").unwrap();
        insert_job(&conn, "job-new", "fresh", None, None, "cmd", "sig").unwrap();

        insert_conversation(&conn, "conv-old", Some("stale")).unwrap();
        conn.execute("UPDATE conversations SET created_at = ?1 WHERE id = 'conv-old'", params![old]).unwrap();
        insert_message(&conn, "conv-old", "user", "hi").unwrap();
        insert_conversation(&conn, "conv-new", Some("fresh")).unwrap();

        let pruned = prune_stale_clients(&conn).unwrap();
        assert_eq!(pruned, 1, "only the stale client row is removed");
        assert!(!client_exists(&conn, "stale").unwrap());
        assert!(client_exists(&conn, "fresh").unwrap());

        let (jobs, convs) = prune_old_data(&conn).unwrap();
        assert_eq!((jobs, convs), (1, 1));
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM job_results WHERE job_id = 'job-old'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 0, "old job results removed with their jobs");
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM messages WHERE conversation_id = 'conv-old'", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 0, "old messages removed with their conversations");
        // Fresh rows untouched.
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM jobs", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1);
    }

    #[test]
    fn find_client_by_hostname_prefers_newest_row() {
        let conn = Connection::open_in_memory().unwrap();
        init(&conn).unwrap();
        upsert_client(&conn, "old-row", "host-x", "W", "10", "x86_64", "", "", "M1").unwrap();
        conn.execute("UPDATE clients SET last_seen = 100 WHERE id = 'old-row'", []).unwrap();
        upsert_client(&conn, "new-row", "host-x", "W", "11", "x86_64", "", "", "M2").unwrap();
        conn.execute("UPDATE clients SET last_seen = 200 WHERE id = 'new-row'", []).unwrap();

        let (id, machine) = find_client_by_hostname(&conn, "host-x").unwrap().unwrap();
        assert_eq!(id, "new-row");
        assert_eq!(machine, "M2");
        assert_eq!(find_client_by_hostname(&conn, "nope").unwrap(), None);
    }
}

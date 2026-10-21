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
CREATE TABLE IF NOT EXISTS client_tokens (
    client_id TEXT PRIMARY KEY,
    token_hash TEXT NOT NULL DEFAULT '',
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
";

/// Current unix epoch seconds.
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

// ---------- device tokens ----------

/// Store the token hash of a client, replacing any previous one.
pub fn set_client_token(
    conn: &Connection,
    client_id: &str,
    token_hash: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO client_tokens (client_id, token_hash, created_at)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(client_id) DO UPDATE SET
            token_hash = excluded.token_hash,
            created_at = excluded.created_at",
        params![client_id, token_hash, now()],
    )?;
    Ok(())
}

/// The token hash of a client, if it has one.
pub fn client_token_hash(conn: &Connection, client_id: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT token_hash FROM client_tokens WHERE client_id = ?1",
        params![client_id],
        |row| row.get::<_, String>(0),
    )
    .optional()
}

/// Drop the token of a client so it registers again.
pub fn clear_client_token(conn: &Connection, client_id: &str) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM client_tokens WHERE client_id = ?1", params![client_id])?;
    Ok(())
}

/// A fresh random token, hex encoded.
///
/// [Note]
/// SQLite draws the bytes from the platform entropy source, so the token
/// does not need a dependency of its own.
pub fn random_token(conn: &Connection) -> rusqlite::Result<String> {
    let bytes: Vec<u8> = conn.query_row("SELECT randomblob(32)", [], |row| row.get(0))?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// Create all tables if missing.
pub fn init(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(SCHEMA)
}

// ---------- clients ----------

#[derive(Debug, Serialize)]
pub struct ClientRow {
    pub id: String,
    pub hostname: String,
    pub os: String,
    pub os_version: String,
    pub arch: String,
    pub last_seen: i64,
    pub created_at: i64,
}

/// Insert or refresh a client row (created_at keeps its original value).
pub fn upsert_client(
    conn: &Connection,
    id: &str,
    hostname: &str,
    os: &str,
    os_version: &str,
    arch: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO clients (id, hostname, os, os_version, arch, last_seen, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
         ON CONFLICT(id) DO UPDATE SET
            hostname = excluded.hostname,
            os = excluded.os,
            os_version = excluded.os_version,
            arch = excluded.arch,
            last_seen = excluded.last_seen",
        params![id, hostname, os, os_version, arch, now()],
    )?;
    Ok(())
}

pub fn list_clients(conn: &Connection) -> rusqlite::Result<Vec<ClientRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, hostname, os, os_version, arch, last_seen, created_at
         FROM clients ORDER BY last_seen DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(ClientRow {
            id: row.get(0)?,
            hostname: row.get(1)?,
            os: row.get(2)?,
            os_version: row.get(3)?,
            arch: row.get(4)?,
            last_seen: row.get(5)?,
            created_at: row.get(6)?,
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

#[derive(Debug, Serialize)]
pub struct JobRow {
    pub id: String,
    pub client_id: String,
    pub package_url: Option<String>,
    pub package_path: Option<String>,
    pub silent_cmd: String,
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
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO jobs (id, client_id, package_url, package_path, silent_cmd, status, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 'pending', ?6)",
        params![id, client_id, package_url, package_path, silent_cmd, now()],
    )?;
    Ok(())
}

fn job_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<JobRow> {
    Ok(JobRow {
        id: row.get(0)?,
        client_id: row.get(1)?,
        package_url: row.get(2)?,
        package_path: row.get(3)?,
        silent_cmd: row.get(4)?,
        status: row.get(5)?,
        created_at: row.get(6)?,
    })
}

/// Jobs still waiting for delivery to a client.
pub fn pending_jobs(conn: &Connection, client_id: &str) -> rusqlite::Result<Vec<JobRow>> {
    let mut stmt = conn.prepare(
        "SELECT id, client_id, package_url, package_path, silent_cmd, status, created_at
         FROM jobs WHERE client_id = ?1 AND status = 'pending' ORDER BY created_at ASC",
    )?;
    let rows = stmt.query_map(params![client_id], job_from_row)?;
    rows.collect()
}

pub fn set_job_status(conn: &Connection, job_id: &str, status: &str) -> rusqlite::Result<()> {
    conn.execute("UPDATE jobs SET status = ?2 WHERE id = ?1", params![job_id, status])?;
    Ok(())
}

/// Store the client's result and advance the job to the reported status.
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
    conn.execute("UPDATE jobs SET status = ?2 WHERE id = ?1", params![job_id, status])?;
    Ok(())
}

/// All jobs with their results (if any), newest first.
pub fn list_jobs(conn: &Connection) -> rusqlite::Result<Vec<JobWithResult>> {
    let mut stmt = conn.prepare(
        "SELECT j.id, j.client_id, j.package_url, j.package_path, j.silent_cmd, j.status, j.created_at,
                r.status, r.output, r.created_at
         FROM jobs j
         LEFT JOIN job_results r ON r.job_id = j.id
         ORDER BY j.created_at DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        let result = match row.get::<_, Option<String>>(7)? {
            None => None,
            Some(status) => Some(JobResultRow {
                job_id: row.get::<_, String>(0)?,
                client_id: row.get::<_, String>(1)?,
                status,
                output: row.get::<_, Option<String>>(8)?.unwrap_or_default(),
                created_at: row.get::<_, Option<i64>>(9)?.unwrap_or(0),
            }),
        };
        Ok(JobWithResult {
            id: row.get(0)?,
            client_id: row.get(1)?,
            package_url: row.get(2)?,
            package_path: row.get(3)?,
            silent_cmd: row.get(4)?,
            status: row.get(5)?,
            created_at: row.get(6)?,
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

pub fn is_conversation_claimed(conn: &Connection, id: &str) -> rusqlite::Result<bool> {
    let claimed: Option<i64> = conn
        .query_row("SELECT claimed FROM conversations WHERE id = ?1", params![id], |row| row.get(0))
        .optional()?;
    Ok(claimed.unwrap_or(0) != 0)
}

/// The client a conversation belongs to, if any.
pub fn conversation_client_id(
    conn: &Connection,
    id: &str,
) -> rusqlite::Result<Option<String>> {
    let client_id: Option<Option<String>> = conn
        .query_row("SELECT client_id FROM conversations WHERE id = ?1", params![id], |row| {
            row.get::<_, Option<String>>(0)
        })
        .optional()?;
    Ok(client_id.flatten())
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

// REST API: client register/inventory/events/jobs, chat conversations with an
// AI-proxied bot, and the admin console API. Handlers map every failure to a
// (StatusCode, String) and never panic; the DB lock is never held across .await.

use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path, Query, Request, State};
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{Html, IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::ai;
use crate::auth;
use crate::db;
use crate::AppState;

pub type SharedState = std::sync::Arc<AppState>;

/// How many recent messages to send to the model as context.
const AI_HISTORY_CAP: i64 = 20;
/// Max events returned by the admin endpoint.
const MAX_EVENTS_RETURNED: i64 = 500;

static ID_COUNTER: AtomicU32 = AtomicU32::new(0);

/// Unique id from wall-clock nanos + a process-local counter (no uuid crate).
fn new_id(prefix: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let n = ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}{nanos:x}{n:x}")
}

// ---------- error helpers ----------

fn internal_error<E: std::fmt::Display>(e: E) -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, format!("internal error: {e}"))
}

fn db_poisoned() -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, "database mutex poisoned".to_string())
}

fn not_found() -> (StatusCode, String) {
    (StatusCode::NOT_FOUND, "not found".to_string())
}

fn unauthorized(message: &str) -> (StatusCode, String) {
    (StatusCode::UNAUTHORIZED, message.to_string())
}

/// Authorise a request that acts on behalf of one client.
///
/// [Note]
/// The device token of the request must match the hash stored for that
/// client. A client without a token, or with the token of another client,
/// is refused.
fn authorize_client(
    state: &SharedState,
    client_id: &str,
    headers: &axum::http::HeaderMap,
) -> Result<(), (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    let stored = db::client_token_hash(&conn, client_id)
        .map_err(internal_error)?
        .unwrap_or_default();
    if stored.is_empty() {
        return Err(unauthorized("the client has no device token"));
    }
    if auth::token_matches(auth::device_token(headers), &stored) {
        Ok(())
    } else {
        Err(unauthorized("invalid device token"))
    }
}

// ---------- router ----------

/// Build the full router: console at "/", APIs nested under /api.
pub fn router(state: SharedState) -> Router {
    Router::new()
        .route("/", get(root_page))
        .nest("/api/client", client_routes())
        .nest("/api/conversations", conversation_routes())
        .nest("/api/admin", admin_routes(state.clone()))
        .with_state(state)
}

/// Refuse a request that does not carry the admin token.
async fn require_admin(
    State(state): State<SharedState>,
    request: Request,
    next: Next,
) -> Response {
    if let Err((status, message)) = state.admin.authorize(request.headers()) {
        return (status, message).into_response();
    }
    next.run(request).await
}

/// Serve the single-file admin console.
async fn root_page() -> Html<&'static str> {
    Html(include_str!("../console/index.html"))
}

fn client_routes() -> Router<SharedState> {
    Router::new()
        .route("/register", post(register_client))
        .route("/:id/inventory", post(client_inventory))
        .route("/:id/events", post(client_events))
        .route("/:id/jobs", get(client_jobs))
        .route("/:id/jobs/:job_id/result", post(client_job_result))
}

fn conversation_routes() -> Router<SharedState> {
    Router::new()
        .route("/", post(create_conversation))
        .route("/:id/messages", post(post_message).get(get_messages))
}

fn admin_routes(state: SharedState) -> Router<SharedState> {
    Router::new()
        .route("/clients", get(admin_clients))
        .route("/clients/:id/inventory", get(admin_inventory))
        .route("/clients/:id/events", get(admin_events))
        .route("/clients/:id/reset-token", post(admin_reset_token))
        .route("/conversations", get(admin_conversations))
        .route("/conversations/:id/messages", get(admin_messages))
        .route("/conversations/:id/claim", post(admin_claim))
        .route("/conversations/:id/reply", post(admin_reply))
        .route("/conversations/:id/close", post(admin_close))
        .route("/jobs", post(admin_create_job).get(admin_list_jobs))
        .layer(axum::middleware::from_fn_with_state(state, require_admin))
}

// ---------- payload types ----------

#[derive(Deserialize)]
struct RegisterIn {
    client_id: String,
    hostname: String,
    os: String,
    os_version: String,
    arch: String,
}

#[derive(Deserialize)]
struct InventoryIn {
    json: String,
}

#[derive(Deserialize)]
struct EventIn {
    source: String,
    text: String,
    created_at: i64,
}

#[derive(Deserialize)]
struct EventsIn {
    events: Vec<EventIn>,
}

#[derive(Deserialize, Default)]
struct ConvIn {
    client_id: Option<String>,
}

#[derive(Deserialize)]
struct MsgIn {
    text: String,
}

#[derive(Deserialize)]
struct ReplyIn {
    text: String,
}

#[derive(Deserialize)]
struct JobIn {
    client_id: String,
    package_url: Option<String>,
    package_path: Option<String>,
    silent_cmd: String,
}

#[derive(Deserialize)]
struct JobResultIn {
    status: String,
    output: String,
}

#[derive(Deserialize)]
struct AfterQuery {
    after: Option<i64>,
}

// ---------- client API ----------

/// Whether a registration may go ahead and issue a token.
///
/// [Note]
/// A client that already has a token keeps it unless the request carries
/// that token, so nobody can take over a client by repeating its id. A
/// client without a stored token -- a fresh one, or one whose token an
/// administrator reset -- gets a new one.
fn registration_allowed(stored_hash: &str, presented_token: &str) -> bool {
    stored_hash.is_empty() || auth::token_matches(presented_token, stored_hash)
}

/// Register a client and hand out its device token.
///
/// [Note]
/// The token is issued once and only its hash is stored. Registering an
/// unknown client id issues a token; registering a known one requires the
/// token that client already has, so nobody can take over a client by
/// repeating its id. A client whose token was reset by an administrator
/// has no token stored and gets a fresh one.
async fn register_client(
    State(state): State<SharedState>,
    headers: axum::http::HeaderMap,
    Json(payload): Json<RegisterIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    let stored = db::client_token_hash(&conn, &payload.client_id)
        .map_err(internal_error)?
        .unwrap_or_default();
    if !registration_allowed(&stored, auth::device_token(&headers)) {
        return Err((
            StatusCode::CONFLICT,
            "the client is already registered; send the current device token".to_string(),
        ));
    }
    db::upsert_client(
        &conn,
        &payload.client_id,
        &payload.hostname,
        &payload.os,
        &payload.os_version,
        &payload.arch,
    )
    .map_err(internal_error)?;
    let token = db::random_token(&conn).map_err(internal_error)?;
    db::set_client_token(&conn, &payload.client_id, &auth::hash_token(&token))
        .map_err(internal_error)?;
    Ok(Json(json!({ "ok": true, "device_token": token })))
}

async fn client_inventory(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
    Json(payload): Json<InventoryIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    authorize_client(&state, &id, &headers)?;
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::save_inventory(&conn, &id, &payload.json).map_err(internal_error)?;
    Ok(Json(json!({ "ok": true })))
}

async fn client_events(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
    Json(payload): Json<EventsIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    authorize_client(&state, &id, &headers)?;
    let batch: Vec<(String, String, i64)> = payload
        .events
        .into_iter()
        .map(|e| (e.source, e.text, e.created_at))
        .collect();
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::insert_events(&conn, &id, &batch).map_err(internal_error)?;
    Ok(Json(json!({ "ok": true })))
}

async fn client_jobs(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
) -> Result<Json<Vec<db::JobRow>>, (StatusCode, String)> {
    authorize_client(&state, &id, &headers)?;
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    let mut jobs = db::pending_jobs(&conn, &id).map_err(internal_error)?;
    // Mark delivered jobs as running so the next poll does not repeat them.
    for job in &jobs {
        db::set_job_status(&conn, &job.id, "running").map_err(internal_error)?;
    }
    for job in &mut jobs {
        job.status = "running".to_string();
    }
    Ok(Json(jobs))
}

async fn client_job_result(
    State(state): State<SharedState>,
    Path((client_id, job_id)): Path<(String, String)>,
    headers: axum::http::HeaderMap,
    Json(payload): Json<JobResultIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    authorize_client(&state, &client_id, &headers)?;
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::save_job_result(&conn, &job_id, &client_id, &payload.status, &payload.output)
        .map_err(internal_error)?;
    Ok(Json(json!({ "ok": true })))
}

// ---------- chat API ----------

/// What the bot should do after a user message is stored.
enum BotAction {
    /// Conversation claimed by an admin — the bot stays silent.
    Skip,
    /// AI env incomplete or URL invalid at startup.
    NotConfigured,
    /// (role, content) history to send to the model.
    Ask(Vec<(String, String)>),
}

async fn create_conversation(
    State(state): State<SharedState>,
    headers: axum::http::HeaderMap,
    body: Option<Json<ConvIn>>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let client_id = body
        .and_then(|Json(payload)| payload.client_id)
        .ok_or_else(|| unauthorized("the conversation needs a client id"))?;
    authorize_client(&state, &client_id, &headers)?;
    let id = new_id("c");
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::insert_conversation(&conn, &id, Some(&client_id)).map_err(internal_error)?;
    Ok(Json(json!({ "conversation_id": id })))
}

async fn post_message(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
    Json(payload): Json<MsgIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    // Scope the lock: dropped before the AI call below.
    let action = {
        let conn = state.db.lock().map_err(|_| db_poisoned())?;
        let owner = db::conversation_client_id(&conn, &id).map_err(internal_error)?;
        let owner = owner.ok_or_else(not_found)?;
        authorize_client(&state, &owner, &headers)?;
        if !db::conversation_exists(&conn, &id).map_err(internal_error)? {
            return Err(not_found());
        }
        db::insert_message(&conn, &id, "user", &payload.text).map_err(internal_error)?;
        if db::is_conversation_claimed(&conn, &id).map_err(internal_error)? {
            BotAction::Skip
        } else if !state.ai.is_configured() {
            BotAction::NotConfigured
        } else {
            BotAction::Ask(db::ai_history(&conn, &id, AI_HISTORY_CAP).map_err(internal_error)?)
        }
    };

    let reply = match action {
        BotAction::Skip => return Ok(Json(json!({ "reply": Value::Null }))),
        BotAction::NotConfigured => "chưa cấu hình AI".to_string(),
        BotAction::Ask(history) => match ai::chat(history).await {
            Ok(text) => text,
            Err(_) => "[AI error]".to_string(),
        },
    };

    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::insert_message(&conn, &id, "bot", &reply).map_err(internal_error)?;
    Ok(Json(json!({ "reply": reply })))
}

async fn get_messages(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
    Query(q): Query<AfterQuery>,
) -> Result<Json<Vec<db::MessageRow>>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    let owner = db::conversation_client_id(&conn, &id)
        .map_err(internal_error)?
        .ok_or_else(not_found)?;
    drop(conn);
    authorize_client(&state, &owner, &headers)?;
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    let messages = db::messages_after(&conn, &id, q.after.unwrap_or(0)).map_err(internal_error)?;
    Ok(Json(messages))
}

// ---------- admin API ----------

async fn admin_clients(
    State(state): State<SharedState>,
) -> Result<Json<Vec<db::ClientRow>>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    Ok(Json(db::list_clients(&conn).map_err(internal_error)?))
}

async fn admin_inventory(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    match db::get_inventory(&conn, &id).map_err(internal_error)? {
        None => Err(not_found()),
        Some((raw, updated_at)) => {
            // Stored text should be JSON; fall back to a raw string value.
            let parsed = serde_json::from_str(&raw).unwrap_or(Value::String(raw));
            Ok(Json(json!({ "client_id": id, "json": parsed, "updated_at": updated_at })))
        }
    }
}

async fn admin_events(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<db::EventRow>>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    Ok(Json(db::list_events(&conn, &id, MAX_EVENTS_RETURNED).map_err(internal_error)?))
}

/// Drop the device token of a client so it can register again.
///
/// [Note]
/// The way back for a client that lost its token. Between this call and
/// the next registration the client id is free for anybody to claim, so
/// the client should register again straight away.
async fn admin_reset_token(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::clear_client_token(&conn, &id).map_err(internal_error)?;
    Ok(Json(json!({ "ok": true, "client_id": id })))
}

async fn admin_conversations(
    State(state): State<SharedState>,
) -> Result<Json<Vec<db::ConversationRow>>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    Ok(Json(db::list_conversations(&conn).map_err(internal_error)?))
}

async fn admin_messages(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<db::MessageRow>>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    Ok(Json(db::messages_after(&conn, &id, 0).map_err(internal_error)?))
}

async fn admin_claim(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    if !db::conversation_exists(&conn, &id).map_err(internal_error)? {
        return Err(not_found());
    }
    db::set_conversation_claimed(&conn, &id).map_err(internal_error)?;
    Ok(Json(json!({ "ok": true })))
}

async fn admin_reply(
    State(state): State<SharedState>,
    Path(id): Path<String>,
    Json(payload): Json<ReplyIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    if !db::conversation_exists(&conn, &id).map_err(internal_error)? {
        return Err(not_found());
    }
    db::insert_message(&conn, &id, "admin", &payload.text).map_err(internal_error)?;
    // Replying also claims the conversation so the bot stays quiet.
    db::set_conversation_claimed(&conn, &id).map_err(internal_error)?;
    Ok(Json(json!({ "ok": true })))
}

async fn admin_close(
    State(state): State<SharedState>,
    Path(id): Path<String>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    if !db::conversation_exists(&conn, &id).map_err(internal_error)? {
        return Err(not_found());
    }
    db::set_conversation_closed(&conn, &id).map_err(internal_error)?;
    Ok(Json(json!({ "ok": true })))
}

async fn admin_create_job(
    State(state): State<SharedState>,
    Json(payload): Json<JobIn>,
) -> Result<Json<Value>, (StatusCode, String)> {
    let id = new_id("j");
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    db::insert_job(
        &conn,
        &id,
        &payload.client_id,
        payload.package_url.as_deref(),
        payload.package_path.as_deref(),
        &payload.silent_cmd,
    )
    .map_err(internal_error)?;
    Ok(Json(json!({ "job_id": id })))
}

async fn admin_list_jobs(
    State(state): State<SharedState>,
) -> Result<Json<Vec<db::JobWithResult>>, (StatusCode, String)> {
    let conn = state.db.lock().map_err(|_| db_poisoned())?;
    Ok(Json(db::list_jobs(&conn).map_err(internal_error)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_known_client_cannot_be_taken_over_without_its_token() {
        let stored = auth::hash_token("original");
        // No token: refused.
        assert!(!registration_allowed(&stored, ""));
        // A wrong token: refused.
        assert!(!registration_allowed(&stored, "guess"));
        // The right token: allowed, so the client can rotate its token.
        assert!(registration_allowed(&stored, "original"));
    }

    #[test]
    fn a_client_without_a_stored_token_may_register() {
        // Fresh client.
        assert!(registration_allowed("", ""));
        // A client whose token an administrator reset.
        assert!(registration_allowed("", "anything"));
    }
}

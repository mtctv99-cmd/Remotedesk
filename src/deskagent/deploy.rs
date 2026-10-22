use hbb_common::{bail, log, ResultType};
use serde_derive::{Deserialize, Serialize};
use std::net::{Ipv4Addr, Ipv6Addr};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::time::Duration;
use url::{Host, Url};
use uuid::Uuid;

use super::secret;

/// Environment variable overriding the Manager base URL.
const MANAGER_URL_ENV: &str = "DESKAGENT_MANAGER_URL";
/// Option key holding the Manager base URL.
const MANAGER_URL_OPTION: &str = "deskagent-manager-url";
/// Manager base URL used when the env var and the option are unset. The
/// Manager runs locally, so the loopback default is expected here.
const DEFAULT_MANAGER_URL: &str = "http://127.0.0.1:8080";
/// Ticks (30s each) between inventory/event uploads: 20 x 30s = 10 min.
const INVENTORY_INTERVAL_TICKS: u32 = 20;
/// Cap on the command output posted back per job.
const MAX_OUTPUT_LEN: usize = 32 * 1024;
/// Delay before the first registration retry, doubled per failure.
const REGISTER_BACKOFF_BASE_SECS: u64 = 60;
/// Upper bound of the registration retry delay.
const REGISTER_BACKOFF_MAX_SECS: u64 = 3600;

/// Counts `tick` calls so inventory uploads run every 10 minutes.
static TICK_COUNT: AtomicU32 = AtomicU32::new(0);
/// Set when the Manager rejected the stored token, so the next tick
/// registers again before polling.
static NEEDS_REGISTRATION: AtomicBool = AtomicBool::new(false);
/// Consecutive failed registrations.
static REGISTER_FAILURES: AtomicU32 = AtomicU32::new(0);
/// Earliest unix time (seconds) of the next registration attempt.
static NEXT_REGISTER_AT: AtomicU64 = AtomicU64::new(0);

/// A deploy job advertised by the Manager.
#[derive(Debug, PartialEq, Default, Serialize, Deserialize, Clone)]
pub struct DeployJob {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub package_url: String,
    #[serde(default)]
    pub package_path: String,
    #[serde(default)]
    pub silent_cmd: String,
}

/// Response body of `GET /api/client/{id}/jobs`.
#[derive(Debug, PartialEq, Default, Serialize, Deserialize, Clone)]
pub struct JobsResponse {
    #[serde(default)]
    pub jobs: Vec<DeployJob>,
}

/// Result body posted to `/api/client/{id}/jobs/{job_id}/result`.
#[derive(Debug, PartialEq, Serialize, Clone)]
pub struct JobResult {
    pub status: String,
    pub output: String,
}

/// Validate a server URL before any request is sent.
///
/// [Note]
/// Only http/https are allowed. The host must not be localhost, loopback,
/// private, link-local, carrier-grade NAT (100.64/10) or reserved
/// (0.0.0.0/8, fc00::/7, fe80::/10), so a server URL cannot point the
/// client at its own network (SSRF guard). The stricter variants in
/// src/hbbs_http/http_client.rs (e.g. `create_http_client_async_with_url_strict`,
/// line 278) only enforce HTTPS and do not block private/loopback hosts,
/// hence this separate helper.
pub fn validate_server_url(url: &str) -> ResultType<Url> {
    let parsed = Url::parse(url)?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        bail!("only http/https schemes are allowed: {}", url);
    }
    match parsed.host() {
        Some(Host::Ipv4(ip)) => {
            if is_forbidden_ipv4(&ip) {
                bail!("host is not allowed: {}", ip);
            }
        }
        Some(Host::Ipv6(ip)) => {
            if is_forbidden_ipv6(&ip) {
                bail!("host is not allowed: {}", ip);
            }
        }
        Some(Host::Domain(domain)) => {
            // A trailing dot keeps a name a public suffix root, treat it the same.
            let d = domain.to_lowercase();
            let d = d.trim_end_matches('.');
            if d == "localhost" || d.ends_with(".localhost") {
                bail!("host is not allowed: {}", domain);
            }
        }
        None => bail!("URL has no host: {}", url),
    }
    Ok(parsed)
}

fn is_forbidden_ipv4(ip: &Ipv4Addr) -> bool {
    let o = ip.octets();
    // 127.0.0.0/8, 10/8, 172.16/12, 192.168/16, 169.254/16
    ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        // 0.0.0.0/8
        || o[0] == 0
        // 100.64.0.0/10 (carrier-grade NAT)
        || (o[0] == 100 && (64..=127).contains(&o[1]))
}

fn is_forbidden_ipv6(ip: &Ipv6Addr) -> bool {
    let seg = ip.segments();
    ip.is_loopback() // ::1
        // fc00::/7 (unique local)
        || (seg[0] & 0xFE00) == 0xFC00
        // fe80::/10 (link local)
        || (seg[0] & 0xFFC0) == 0xFE80
}

/// Append `path` to a validated base URL with a single `/` separator.
pub fn join_path(base: &Url, path: &str) -> String {
    let mut url = base.to_string();
    if !url.ends_with('/') {
        url.push('/');
    }
    format!("{}{}", url, path)
}

/// Validate the Manager base URL or a package URL.
///
/// [Note]
/// Unlike [`validate_server_url`] this only enforces the http/https
/// scheme: the Manager runs on localhost by default and package mirrors
/// may sit on private hosts, so the strict SSRF guard (no
/// loopback/private/reserved) is intentionally not applied here; that
/// guard belongs to the Manager-side AI proxy.
fn validate_http_url(url: &str) -> ResultType<Url> {
    let parsed = Url::parse(url)?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        bail!("only http/https schemes are allowed: {}", url);
    }
    if parsed.host().is_none() {
        bail!("URL has no host: {}", url);
    }
    Ok(parsed)
}

/// Resolve the Manager base URL from `DESKAGENT_MANAGER_URL`, else the
/// `deskagent-manager-url` option, else the `api-server` option, else the
/// loopback default.
///
/// [Note]
/// The Manager serves the api and the admin console on the same port, so a
/// deployment that points `api-server` at the Manager keeps working. The
/// dedicated option comes first for the deployments that run the api
/// somewhere else.
fn manager_base_url() -> ResultType<Url> {
    let env_url = std::env::var_os(MANAGER_URL_ENV)
        .map(|v| v.to_string_lossy().into_owned())
        .unwrap_or_default();
    resolve_manager_url(
        &env_url,
        &hbb_common::config::Config::get_option(MANAGER_URL_OPTION),
        &hbb_common::config::Config::get_option("api-server"),
    )
}

fn resolve_manager_url(env_url: &str, option_url: &str, api_server: &str) -> ResultType<Url> {
    let mut raw = if env_url.trim().is_empty() {
        if option_url.trim().is_empty() {
            api_server.trim().to_owned()
        } else {
            option_url.trim().to_owned()
        }
    } else {
        env_url.trim().to_owned()
    };
    if raw.is_empty() {
        raw = DEFAULT_MANAGER_URL.to_owned();
    }
    // Trim trailing slashes so join_path yields single-slash URLs.
    while raw.ends_with('/') {
        raw.pop();
    }
    validate_http_url(&raw)
}

/// Blocking HTTP agent for the daemon: 10s connect, 60s overall.
fn manager_agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(10))
        .timeout(Duration::from_secs(60))
        .build()
}

/// Path of the persisted Manager client id.
fn client_id_path() -> PathBuf {
    manager_file_path("manager_client_id")
}

/// Path of the persisted per-client Manager token, issued at registration.
fn device_token_path() -> PathBuf {
    manager_file_path("manager_device_token")
}

/// Path of the client id the Manager bound this client to.
fn manager_bound_id_path() -> PathBuf {
    manager_file_path("manager_bound_id")
}

/// Path of the marker recording that the Manager issues no device token.
fn token_state_path() -> PathBuf {
    manager_file_path("manager_token_state")
}

fn manager_file_path(name: &str) -> PathBuf {
    let mut dir = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    dir.push("DeskAgent");
    dir.push(name);
    dir
}

/// The client id the Manager recognises this client as.
///
/// [Note]
/// The Manager keeps one row per machine and binds the device token to it,
/// so a second instance of the same machine gets a token for the canonical
/// row. The requests have to use that id, otherwise the Manager refuses
/// them as a client id mismatch.
fn manager_bound_id(local_id: &str) -> String {
    match std::fs::read_to_string(manager_bound_id_path()) {
        Ok(s) => {
            let s = s.trim().to_owned();
            if s.is_empty() {
                local_id.to_owned()
            } else {
                s
            }
        }
        Err(_) => local_id.to_owned(),
    }
}

/// Read the persisted device token, or an empty string when unregistered.
fn load_device_token() -> String {
    secret::read_secret(&device_token_path()).unwrap_or_default()
}

/// Whether the Manager is known not to issue device tokens.
///
/// [Note]
/// Recorded once, when a registration answered without a token. Without
/// it the client would re-register on every tick, because the token stays
/// empty forever.
fn manager_issues_no_tokens() -> bool {
    std::fs::read_to_string(token_state_path())
        .map(|s| s.trim() == "no-token")
        .unwrap_or(false)
}

/// Attach the device token when the Manager issued one. The token is
/// optional: a Manager that does not require it ignores the header.
fn with_token(req: ureq::Request, token: &str) -> ureq::Request {
    if token.is_empty() {
        req
    } else {
        req.set("X-Device-Token", token)
    }
}

/// Load the persisted client id, or generate + persist a new uuid v4.
///
/// [Note]
/// Returns `(id, is_new)`; `is_new` tells the caller to register the
/// client with the Manager. Persistence failures are logged and ignored,
/// so the daemon keeps working with an in-memory id.
fn load_or_create_client_id() -> (String, bool) {
    let path = client_id_path();
    if let Ok(id) = std::fs::read_to_string(&path) {
        let id = id.trim().to_owned();
        if !id.is_empty() {
            return (id, false);
        }
    }
    let id = Uuid::new_v4().to_string();
    if let Some(parent) = path.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            log::warn!(
                "failed to create the DeskAgent data dir {:?}: {}",
                parent,
                e
            );
        }
    }
    if let Err(e) = std::fs::write(&path, &id) {
        log::warn!("failed to persist the manager client id: {}", e);
    }
    (id, true)
}

/// What the Manager answered when the client registered.
#[derive(Debug, PartialEq)]
enum Registration {
    /// The Manager issued a device token; it has been persisted.
    TokenIssued,
    /// The Manager does not use device tokens.
    NoToken,
}

/// The stable per-machine identity the Manager uses to recognise this
/// client again after a reinstall or a new client id.
///
/// [Note]
/// On Windows this is the MachineGuid, exactly the value the Manager
/// stores. Without it the Manager cannot tell that a register belongs to a
/// client it already knows and refuses it.
fn machine_id() -> String {
    hbb_common::machine_uid::get().unwrap_or_default().trim().to_owned()
}

/// Register the client with the Manager and persist the device token it
/// hands back.
///
/// [Note]
/// The answer decides whether the client has to register again: a
/// Manager that issues no token is recorded once, so an install without a
/// token does not re-register on every tick. The current token is sent
/// along, because a Manager only hands out a new one to a client that
/// proves it owns the id.
fn register_client(
    agent: &ureq::Agent,
    base: &Url,
    client_id: &str,
    token: &str,
) -> ResultType<Registration> {
    let info = super::system_info::collect()?;
    let url = join_path(base, "api/client/register");
    let body = serde_json::json!({
        "client_id": client_id,
        "hostname": info.hostname,
        "os": info.os,
        "os_version": info.os_version,
        "arch": info.arch,
        "version": env!("CARGO_PKG_VERSION"),
        "machine_id": machine_id(),
    });
    let resp = with_token(agent.post(&url), token)
        .set("Content-Type", "application/json")
        .send_string(&body.to_string())?;
    let answer = resp
        .into_string()
        .ok()
        .and_then(|b| serde_json::from_str::<serde_json::Value>(&b).ok())
        .unwrap_or(serde_json::Value::Null);
    // The Manager may answer with the canonical row it bound this machine
    // to; the requests have to use that id.
    if let Some(bound) = answer.get("client_id").and_then(|v| v.as_str()) {
        if !bound.is_empty() && bound != client_id {
            if let Err(e) = std::fs::write(manager_bound_id_path(), bound) {
                log::warn!("failed to persist the manager bound client id: {}", e);
            }
        }
    }
    let token = answer
        .get("device_token")
        .and_then(|v| v.as_str())
        .map(str::to_owned)
        .unwrap_or_default();
    if token.is_empty() {
        if let Err(e) = std::fs::write(token_state_path(), "no-token") {
            log::warn!("failed to record the manager token state: {}", e);
        }
        return Ok(Registration::NoToken);
    }
    if let Err(e) = secret::write_secret(&device_token_path(), &token) {
        bail!("failed to persist the manager device token: {}", e);
    }
    // Mirror into the local option store so the Flutter side (chat attachment
    // upload, Tools Sự kiện tab) can send X-Device-Token without reading the
    // obfuscated secret file.
    hbb_common::config::Config::set_option("manager-device-token".into(), token.clone());
    // The Manager issues tokens again, so the earlier marker is stale.
    let _ = std::fs::remove_file(token_state_path());
    Ok(Registration::TokenIssued)
}

/// Delay before the next registration attempt, doubling per failure.
fn register_backoff_secs(failures: u32) -> u64 {
    let shift = failures.saturating_sub(1).min(6);
    REGISTER_BACKOFF_BASE_SECS
        .saturating_mul(1u64 << shift)
        .min(REGISTER_BACKOFF_MAX_SECS)
}

/// The current unix time in seconds.
fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Whether a registration attempt is due.
fn register_due() -> bool {
    unix_now() >= NEXT_REGISTER_AT.load(Ordering::Relaxed)
}

/// Whether the client still has to register with the Manager.
///
/// [Note]
/// A new client id always needs one. An install that already has an id
/// needs one when the Manager rejected its token, or when the Manager
/// issues tokens but the stored one is gone. A Manager that does not
/// issue tokens is recorded once, so the client does not re-register on
/// every tick.
fn needs_registration(is_new: bool, token: &str) -> bool {
    if !register_due() {
        return false;
    }
    if is_new {
        return true;
    }
    if NEEDS_REGISTRATION.swap(false, Ordering::Relaxed) {
        return true;
    }
    if !token.is_empty() {
        return false;
    }
    !manager_issues_no_tokens()
}

/// Run one daemon cycle: upload inventory/events every 10 minutes and
/// poll for pending jobs.
///
/// [Note]
/// Called every 30s by the background thread in `super`. Individual job
/// failures are reported to the Manager and never abort the tick; only a
/// failed job poll aborts the tick (the caller logs and retries).
pub fn tick() -> ResultType<()> {
    let agent = manager_agent();
    let base = manager_base_url()?;
    let (client_id, is_new) = load_or_create_client_id();
    let current_token = load_device_token();
    if needs_registration(is_new, &current_token) {
        match register_client(&agent, &base, &client_id, &current_token) {
            Ok(Registration::TokenIssued) | Ok(Registration::NoToken) => {
                REGISTER_FAILURES.store(0, Ordering::Relaxed);
                NEXT_REGISTER_AT.store(0, Ordering::Relaxed);
            }
            Err(e) => {
                let failures = REGISTER_FAILURES.fetch_add(1, Ordering::Relaxed) + 1;
                let delay = register_backoff_secs(failures);
                NEXT_REGISTER_AT.store(unix_now() + delay, Ordering::Relaxed);
                log::error!(
                    "manager registration failed ({} in a row), retrying in {}s: {}",
                    failures,
                    delay,
                    e
                );
            }
        }
    }
    let token = load_device_token();
    // The Manager may have bound this machine to another row; the token is
    // only valid for that row.
    let client_id = manager_bound_id(&client_id);
    // (a) Inventory + event upload every 20 ticks (10 minutes).
    let n = TICK_COUNT.fetch_add(1, Ordering::Relaxed);
    if n % INVENTORY_INTERVAL_TICKS == 0 {
        upload_inventory(&agent, &base, &client_id, &token);
    }
    // (b) Job poll on every tick.
    let jobs = fetch_jobs(&agent, &base, &client_id, &token)?;
    for job in jobs {
        if !job.status.eq_ignore_ascii_case("pending") {
            continue;
        }
        process_job(&agent, &base, &client_id, &token, &job);
    }
    Ok(())
}

/// Whether a Manager answer rejected the credential.
///
/// [Note]
/// A rejected token is remembered so the next tick registers again
/// instead of polling with a credential that can never work.
fn is_auth_rejection(e: &ureq::Error) -> bool {
    matches!(e, ureq::Error::Status(401, _) | ureq::Error::Status(403, _))
}

/// POST the system inventory and the event logs to the Manager.
fn upload_inventory(agent: &ureq::Agent, base: &Url, client_id: &str, token: &str) {
    let inv = match super::system_info::collect_system_info() {
        Ok(v) => v,
        Err(e) => {
            log::warn!("collect_system_info failed: {}", e);
            return;
        }
    };
    let url = join_path(base, &format!("api/client/{}/inventory", client_id));
    // The manager stores the inventory as the text of a "json" field.
    let body = serde_json::json!({ "json": inv }).to_string();
    if let Err(e) = with_token(agent.post(&url), token)
        .set("Content-Type", "application/json")
        .send_string(&body)
    {
        if is_auth_rejection(&e) {
            NEEDS_REGISTRATION.store(true, Ordering::Relaxed);
            log::error!("the manager rejected the device token on the inventory upload");
        } else {
            log::warn!("inventory upload failed: {}", e);
        }
    }
    let events = match super::system_info::collect_events() {
        Ok(v) => v,
        Err(e) => {
            log::warn!("collect_events failed: {}", e);
            return;
        }
    };
    let url = join_path(base, &format!("api/client/{}/events", client_id));
    let body = serde_json::json!({ "events": events }).to_string();
    if let Err(e) = with_token(agent.post(&url), token)
        .set("Content-Type", "application/json")
        .send_string(&body)
    {
        if is_auth_rejection(&e) {
            NEEDS_REGISTRATION.store(true, Ordering::Relaxed);
            log::error!("the manager rejected the device token on the event upload");
        } else {
            log::warn!("event upload failed: {}", e);
        }
    }
}

/// GET the job list from the Manager.
fn fetch_jobs(
    agent: &ureq::Agent,
    base: &Url,
    client_id: &str,
    token: &str,
) -> ResultType<Vec<DeployJob>> {
    let url = join_path(base, &format!("api/client/{}/jobs", client_id));
    let body = match with_token(agent.get(&url), token).call() {
        Ok(resp) => resp.into_string()?,
        Err(e) if is_auth_rejection(&e) => {
            NEEDS_REGISTRATION.store(true, Ordering::Relaxed);
            bail!("the manager rejected the device token");
        }
        Err(e) => return Err(e.into()),
    };
    // Accept either {"jobs": [...]} or a bare [...] response.
    let jobs = if let Ok(resp) = serde_json::from_str::<JobsResponse>(&body) {
        resp.jobs
    } else {
        serde_json::from_str::<Vec<DeployJob>>(&body)?
    };
    Ok(jobs)
}

/// Handle one pending job and report the outcome to the Manager.
///
/// [Note]
/// Any error becomes a `failed` result POST; a failed result POST is
/// only logged. Never returns `Err` so one bad job cannot break the
/// tick loop.
fn process_job(agent: &ureq::Agent, base: &Url, client_id: &str, token: &str, job: &DeployJob) {
    if job.id.is_empty() {
        log::warn!("deploy job without id skipped");
        return;
    }
    let (status, output) = match run_job(agent, job) {
        Ok(out) => ("success", out),
        Err(e) => ("failed", format!("error: {}", e)),
    };
    let url = join_path(
        base,
        &format!("api/client/{}/jobs/{}/result", client_id, job.id),
    );
    let body = JobResult {
        status: status.to_owned(),
        output: truncate_output(&output),
    };
    if let Err(e) = with_token(agent.post(&url), token)
        .set("Content-Type", "application/json")
        .send_string(&serde_json::to_string(&body).unwrap_or_default())
    {
        log::warn!("failed to report the result of job {}: {}", job.id, e);
    }
    log::info!("deploy job {} finished: {}", job.id, status);
}

/// Download/locate the package and run the job's silent command.
///
/// Returns the raw output text on success; any failure is an `Err`.
fn run_job(agent: &ureq::Agent, job: &DeployJob) -> ResultType<String> {
    let mut workdir: Option<PathBuf> = None;
    let mut lines: Vec<String> = Vec::new();
    if !job.package_url.is_empty() {
        let parsed = validate_http_url(&job.package_url)?;
        let dest_dir = job_download_dir(&job.id);
        let dest = download_package(agent, &parsed, &dest_dir)?;
        lines.push(format!("downloaded: {}", dest.display()));
        workdir = Some(dest_dir);
    } else if !job.package_path.is_empty() {
        let path = PathBuf::from(&job.package_path);
        if !path.is_file() {
            bail!("package_path does not exist: {}", job.package_path);
        }
        lines.push(format!("package: {}", path.display()));
        workdir = path.parent().map(|p| p.to_path_buf());
    }
    if job.silent_cmd.is_empty() {
        lines.push("no silent_cmd; package prepared only".to_owned());
        return Ok(lines.join("\n"));
    }
    let (code, stdout, stderr) = run_silent_cmd(&job.silent_cmd, workdir.as_deref())?;
    lines.push(format!("exit_code: {}", code));
    lines.push(format!("stdout:\n{}", stdout.trim_end()));
    lines.push(format!("stderr:\n{}", stderr.trim_end()));
    if code != 0 {
        bail!("{}", lines.join("\n"));
    }
    Ok(lines.join("\n"))
}

/// Download directory for a job package: %TEMP%/DeskAgent/{job_id}/.
fn job_download_dir(job_id: &str) -> PathBuf {
    let mut dir = std::env::temp_dir();
    dir.push("DeskAgent");
    dir.push(sanitize_path_component(job_id));
    dir
}

/// Reduce a string to a safe single path component.
fn sanitize_path_component(s: &str) -> String {
    let cleaned: String = s
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() {
        "unknown".to_owned()
    } else {
        cleaned
    }
}

/// Download a package into `dest_dir` and return the file path.
fn download_package(agent: &ureq::Agent, package: &Url, dest_dir: &Path) -> ResultType<PathBuf> {
    let filename = package
        .path_segments()
        .and_then(|mut segs| segs.next_back())
        .filter(|s| !s.is_empty() && *s != "." && *s != "..")
        .map(sanitize_path_component)
        .unwrap_or_else(|| "package.bin".to_owned());
    std::fs::create_dir_all(dest_dir)?;
    let dest = dest_dir.join(filename);
    let resp = agent.get(package.as_str()).call()?;
    let mut reader = resp.into_reader();
    let mut file = std::fs::File::create(&dest)?;
    std::io::copy(&mut reader, &mut file)?;
    Ok(dest)
}

/// Run a silent install command via `cmd /C`, capturing exit code and
/// stdout/stderr.
fn run_silent_cmd(silent_cmd: &str, workdir: Option<&Path>) -> ResultType<(i32, String, String)> {
    let mut cmd = Command::new("cmd");
    cmd.args(["/C", silent_cmd]);
    if let Some(dir) = workdir {
        cmd.current_dir(dir);
    }
    hide_window(&mut cmd);
    let out = cmd.output()?;
    Ok((
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    ))
}

/// Keep console children from flashing a window when run from the GUI.
fn hide_window(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

/// Cap posted output so a chatty installer cannot flood the Manager.
fn truncate_output(s: &str) -> String {
    if s.len() <= MAX_OUTPUT_LEN {
        return s.to_owned();
    }
    let mut end = MAX_OUTPUT_LEN;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}\n... (truncated)", &s[..end])
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_validate_server_url_allowed() {
        assert!(validate_server_url("https://example.com").is_ok());
        assert!(validate_server_url("http://example.com:21116").is_ok());
        assert!(validate_server_url("https://my.example.com/path?x=1").is_ok());
        // Outside 100.64/10 and 172.16/12.
        assert!(validate_server_url("http://100.128.0.1/").is_ok());
        assert!(validate_server_url("http://172.32.0.1/").is_ok());
    }

    #[test]
    fn test_validate_server_url_rejected() {
        // Scheme must be http/https.
        assert!(validate_server_url("ftp://example.com").is_err());
        // Localhost and loopback.
        assert!(validate_server_url("http://localhost").is_err());
        assert!(validate_server_url("http://localhost:21116").is_err());
        assert!(validate_server_url("http://sub.localhost").is_err());
        assert!(validate_server_url("http://127.0.0.1:21114").is_err());
        assert!(validate_server_url("http://[::1]/").is_err());
        // Private ranges.
        assert!(validate_server_url("http://10.0.0.2/").is_err());
        assert!(validate_server_url("http://172.16.1.1/").is_err());
        assert!(validate_server_url("http://172.31.255.255/").is_err());
        assert!(validate_server_url("http://192.168.1.1/").is_err());
        // Link-local, carrier-grade NAT and reserved.
        assert!(validate_server_url("http://169.254.1.1/").is_err());
        assert!(validate_server_url("http://100.64.0.1/").is_err());
        assert!(validate_server_url("http://0.1.2.3/").is_err());
        assert!(validate_server_url("http://[fc00::1]/").is_err());
        assert!(validate_server_url("http://[fe80::1]/").is_err());
        // Userinfo must not bypass the host check.
        assert!(validate_server_url("http://user@127.0.0.1/").is_err());
    }

    #[test]
    fn test_validate_http_url_scheme_only() {
        // The Manager runs locally, so loopback/private hosts are allowed.
        assert!(validate_http_url("http://127.0.0.1:8080").is_ok());
        assert!(validate_http_url("http://localhost:8080").is_ok());
        assert!(validate_http_url("http://192.168.1.10:9000/").is_ok());
        assert!(validate_http_url("https://example.com/pkg/setup.msi").is_ok());
        // But the scheme is still enforced.
        assert!(validate_http_url("ftp://example.com/pkg").is_err());
        assert!(validate_http_url("file:///C:/pkg").is_err());
        assert!(validate_http_url("not a url").is_err());
    }

    #[test]
    fn test_resolve_manager_url() {
        // No env var, no option and no api-server: the loopback default.
        // Url::parse appends a trailing '/' for the empty path.
        assert_eq!(
            resolve_manager_url("", "", "").unwrap().as_str(),
            "http://127.0.0.1:8080/"
        );
        // A deployed client points at a remote Manager through the
        // `deskagent-manager-url` option; the daemon must follow it
        // instead of dialing loopback.
        assert_eq!(
            resolve_manager_url("", "http://192.168.232.129:8080", "")
                .unwrap()
                .as_str(),
            "http://192.168.232.129:8080/"
        );
        // A deployment that runs the api and the Manager on the same port
        // points `api-server` at it; that keeps working.
        assert_eq!(
            resolve_manager_url("", "", "http://192.168.232.129:8080")
                .unwrap()
                .as_str(),
            "http://192.168.232.129:8080/"
        );
        // The dedicated option wins over the api server.
        assert_eq!(
            resolve_manager_url("", "http://manager:8080", "http://api:21116")
                .unwrap()
                .as_str(),
            "http://manager:8080/"
        );
        // The env var still wins over the option.
        assert_eq!(
            resolve_manager_url("http://10.0.0.5:9000", "http://192.168.232.129:8080", "")
                .unwrap()
                .as_str(),
            "http://10.0.0.5:9000/"
        );
    }

    #[test]
    fn test_register_backoff_grows_and_is_capped() {
        assert_eq!(register_backoff_secs(1), 60);
        assert_eq!(register_backoff_secs(2), 120);
        assert_eq!(register_backoff_secs(3), 240);
        assert_eq!(register_backoff_secs(10), REGISTER_BACKOFF_MAX_SECS);
    }

    #[test]
    fn test_needs_registration_skips_a_manager_without_tokens() {
        // A client that already has a token does not register again.
        assert!(!needs_registration(false, "a-token"));
        // A brand new client always registers.
        assert!(needs_registration(true, ""));
    }

    #[test]
    fn test_sanitize_path_component() {
        assert_eq!(sanitize_path_component("a-b_1"), "a-b_1");
        // Every non [A-Za-z0-9_-] char, including '..', becomes '_'.
        assert_eq!(sanitize_path_component("../x y"), "___x_y");
        assert_eq!(sanitize_path_component(""), "unknown");
    }

    #[test]
    fn test_truncate_output() {
        assert_eq!(truncate_output("short"), "short");
        let long = "x".repeat(MAX_OUTPUT_LEN + 10);
        let t = truncate_output(&long);
        assert!(t.starts_with(&"x".repeat(MAX_OUTPUT_LEN)));
        assert!(t.ends_with("... (truncated)"));
        // A multi-byte boundary must not panic.
        let wide = "€".repeat(MAX_OUTPUT_LEN);
        let t = truncate_output(&wide);
        assert!(t.ends_with("... (truncated)"));
    }

    #[test]
    fn test_job_serde_defaults() {
        let job: DeployJob = serde_json::from_str(r#"{"id":"j1","status":"pending"}"#).unwrap();
        assert_eq!(job.id, "j1");
        assert_eq!(job.name, "");
        assert_eq!(job.package_url, "");
        assert_eq!(job.silent_cmd, "");
        let jobs: JobsResponse =
            serde_json::from_str(r#"{"jobs":[{"id":"j1","status":"pending"}]}"#).unwrap();
        assert_eq!(jobs.jobs.len(), 1);
        assert_eq!(jobs.jobs[0].id, "j1");
    }

    #[test]
    fn test_join_path() {
        let base = Url::parse("https://example.com").unwrap();
        assert_eq!(join_path(&base, "api/x"), "https://example.com/api/x");
    }
}

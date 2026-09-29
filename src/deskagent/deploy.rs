use hbb_common::{bail, log, ResultType};
use serde_derive::{Deserialize, Serialize};
use std::net::{Ipv4Addr, Ipv6Addr};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;
use url::{Host, Url};
use uuid::Uuid;

/// Environment variable overriding the Manager base URL.
const MANAGER_URL_ENV: &str = "DESKAGENT_MANAGER_URL";
/// Manager base URL used when the env var is unset. The Manager runs
/// locally, so the loopback default is expected here.
const DEFAULT_MANAGER_URL: &str = "http://127.0.0.1:8080";
/// Ticks (30s each) between inventory/event uploads: 20 x 30s = 10 min.
const INVENTORY_INTERVAL_TICKS: u32 = 20;
/// Cap on the command output posted back per job.
const MAX_OUTPUT_LEN: usize = 32 * 1024;

/// Counts `tick` calls so inventory uploads run every 10 minutes.
static TICK_COUNT: AtomicU32 = AtomicU32::new(0);

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

/// Resolve the Manager base URL from `DESKAGENT_MANAGER_URL`.
fn manager_base_url() -> ResultType<Url> {
    let raw = std::env::var_os(MANAGER_URL_ENV)
        .map(|v| v.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut raw = raw.trim().to_owned();
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
    let mut dir = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    dir.push("DeskAgent");
    dir.push("manager_client_id");
    dir
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
            log::warn!("failed to create the DeskAgent data dir {:?}: {}", parent, e);
        }
    }
    if let Err(e) = std::fs::write(&path, &id) {
        log::warn!("failed to persist the manager client id: {}", e);
    }
    (id, true)
}

/// Register a freshly generated client id with the Manager.
fn register_client(agent: &ureq::Agent, base: &Url, client_id: &str) -> ResultType<()> {
    let info = super::system_info::collect()?;
    let url = join_path(base, "api/client/register");
    let body = serde_json::json!({
        "client_id": client_id,
        "hostname": info.hostname,
        "os": info.os,
        "os_version": info.os_version,
        "arch": info.arch,
    });
    agent
        .post(&url)
        .set("Content-Type", "application/json")
        .send_string(&body.to_string())?;
    Ok(())
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
    if is_new {
        if let Err(e) = register_client(&agent, &base, &client_id) {
            log::warn!("manager registration failed: {}", e);
        }
    }
    // (a) Inventory + event upload every 20 ticks (10 minutes).
    let n = TICK_COUNT.fetch_add(1, Ordering::Relaxed);
    if n % INVENTORY_INTERVAL_TICKS == 0 {
        upload_inventory(&agent, &base, &client_id);
    }
    // (b) Job poll on every tick.
    let jobs = fetch_jobs(&agent, &base, &client_id)?;
    for job in jobs {
        if !job.status.eq_ignore_ascii_case("pending") {
            continue;
        }
        process_job(&agent, &base, &client_id, &job);
    }
    Ok(())
}

/// POST the system inventory and the event logs to the Manager.
fn upload_inventory(agent: &ureq::Agent, base: &Url, client_id: &str) {
    let inv = match super::system_info::collect_system_info() {
        Ok(v) => v,
        Err(e) => {
            log::warn!("collect_system_info failed: {}", e);
            return;
        }
    };
    let url = join_path(base, &format!("api/client/{}/inventory", client_id));
    if let Err(e) = agent
        .post(&url)
        .set("Content-Type", "application/json")
        .send_string(&inv)
    {
        log::warn!("inventory upload failed: {}", e);
    }
    let events = match super::system_info::collect_events() {
        Ok(v) => v,
        Err(e) => {
            log::warn!("collect_events failed: {}", e);
            return;
        }
    };
    let url = join_path(base, &format!("api/client/{}/events", client_id));
    if let Err(e) = agent
        .post(&url)
        .set("Content-Type", "application/json")
        .send_string(&events)
    {
        log::warn!("event upload failed: {}", e);
    }
}

/// GET the job list from the Manager.
fn fetch_jobs(agent: &ureq::Agent, base: &Url, client_id: &str) -> ResultType<Vec<DeployJob>> {
    let url = join_path(base, &format!("api/client/{}/jobs", client_id));
    let body = agent.get(&url).call()?.into_string()?;
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
fn process_job(agent: &ureq::Agent, base: &Url, client_id: &str, job: &DeployJob) {
    if job.id.is_empty() {
        log::warn!("deploy job without id skipped");
        return;
    }
    let (status, output) = match run_job(agent, job) {
        Ok(out) => ("success", out),
        Err(e) => ("failed", format!("error: {}", e)),
    };
    let url = join_path(base, &format!("api/client/{}/jobs/{}/result", client_id, job.id));
    let body = JobResult {
        status: status.to_owned(),
        output: truncate_output(&output),
    };
    if let Err(e) = agent
        .post(&url)
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
    fn test_manager_base_url_default() {
        // No env var: the default loopback Manager URL. Url::parse appends
        // a trailing '/' for the empty path.
        std::env::remove_var(MANAGER_URL_ENV);
        let base = manager_base_url().unwrap();
        assert_eq!(base.as_str(), "http://127.0.0.1:8080/");
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

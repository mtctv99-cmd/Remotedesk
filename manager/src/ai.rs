// Outbound AI proxy (OpenAI-compatible chat completions) with a mandatory
// SSRF guard. Every outbound call — at startup and per request — goes through
// validate_outbound_url, which blocks localhost/loopback/private/link-local/
// reserved targets, following the pattern in src/deskagent/deploy.rs
// (is_forbidden_ipv4 / is_forbidden_ipv6).

use std::env;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, ToSocketAddrs};
use std::time::Duration;

use serde_json::json;

pub const ENV_URL: &str = "DESKAGENT_AI_URL";
pub const ENV_KEY: &str = "DESKAGENT_AI_KEY";
pub const ENV_MODEL: &str = "DESKAGENT_AI_MODEL";
pub const ENV_HOSTS: &str = "DESKAGENT_AI_HOSTS";

const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

/// AI proxy config read from env once at startup.
#[derive(Debug)]
pub struct AiConfig {
    pub url: String,
    pub key: String,
    pub model: String,
    /// True only when URL/KEY/MODEL are all set and the URL passes validation.
    pub valid: bool,
    /// Why the bot is disabled, for the startup log.
    pub reason: String,
}

impl AiConfig {
    /// Read env vars and validate the URL once at startup. Invalid config
    /// disables the bot (it replies "chưa cấu hình AI"); the server still runs.
    pub fn from_env() -> Self {
        let url = env::var(ENV_URL).unwrap_or_default();
        let key = env::var(ENV_KEY).unwrap_or_default();
        let model = env::var(ENV_MODEL).unwrap_or_default();

        if url.is_empty() || key.is_empty() || model.is_empty() {
            return Self {
                url,
                key,
                model,
                valid: false,
                reason: format!("{ENV_URL} / {ENV_KEY} / {ENV_MODEL} not all set"),
            };
        }
        match validate_outbound_url(&url) {
            Ok(()) => Self { url, key, model, valid: true, reason: String::new() },
            Err(e) => Self { url, key, model, valid: false, reason: e },
        }
    }

    pub fn is_configured(&self) -> bool {
        self.valid
    }
}

/// Validate an outbound URL before any request is sent.
///
/// Only http/https. Host is parsed manually with std (no url crate): the
/// authority ends at the first '/', '?' or '#'; userinfo before '@' is
/// dropped; IPv6 literals are wrapped in [ ]. Blocked: "localhost", ".localhost",
/// ".local" names, forbidden IPv4/IPv6 ranges, and any IP the hostname
/// resolves to. If DESKAGENT_AI_HOSTS is set (comma separated), the host must
/// be listed there (case-insensitive, name only, no port).
///
/// Known gap: DNS may re-resolve after this check (TOCTOU), see plan risk #10.
pub fn validate_outbound_url(url: &str) -> Result<(), String> {
    let (scheme, rest) = url
        .split_once("://")
        .ok_or_else(|| format!("URL missing scheme: {url}"))?;
    if scheme != "http" && scheme != "https" {
        return Err(format!("scheme not allowed (http/https only): {scheme}"));
    }

    // Authority ends at the first path/query/fragment character.
    let end = rest.find(&['/', '?', '#'][..]).unwrap_or(rest.len());
    let mut authority = &rest[..end];

    // Drop userinfo (user:pass@host) — keep the part after the last '@'.
    if let Some(at) = authority.rfind('@') {
        authority = &authority[at + 1..];
    }
    if authority.is_empty() {
        return Err(format!("URL has no host: {url}"));
    }

    // Extract the host: IPv6 literals live inside [ ].
    let raw_host = if let Some(stripped) = authority.strip_prefix('[') {
        let close = stripped
            .find(']')
            .ok_or_else(|| format!("unclosed IPv6 literal: {url}"))?;
        &stripped[..close]
    } else {
        authority.split(':').next().unwrap_or("") // drop :port
    };
    let host = raw_host.trim_end_matches('.').to_lowercase();
    if host.is_empty() {
        return Err(format!("URL has no host: {url}"));
    }

    // Name-based blocks.
    if host == "localhost" || host.ends_with(".localhost") || host.ends_with(".local") {
        return Err(format!("host is not allowed: {host}"));
    }

    // Optional allowlist, host name only, case-insensitive.
    if let Ok(list) = env::var(ENV_HOSTS) {
        let allowed: Vec<&str> = list.split(',').map(str::trim).filter(|s| !s.is_empty()).collect();
        if !allowed.is_empty() && !allowed.iter().any(|a| a.eq_ignore_ascii_case(&host)) {
            return Err(format!("host {host} is not in {ENV_HOSTS} allowlist"));
        }
    }

    // Literal IP checks (no DNS needed).
    if let Ok(ip4) = host.parse::<Ipv4Addr>() {
        if is_forbidden_ipv4(&ip4) {
            return Err(format!("host is not allowed: {ip4}"));
        }
        return Ok(());
    }
    if let Ok(ip6) = host.parse::<Ipv6Addr>() {
        if is_forbidden_ipv6(&ip6) {
            return Err(format!("host is not allowed: {ip6}"));
        }
        return Ok(());
    }

    // Resolve the hostname and re-check every address, so a public name that
    // points at an internal IP is rejected. Fail closed on resolution errors.
    let addrs: Vec<SocketAddr> = (host.as_str(), 0u16)
        .to_socket_addrs()
        .map_err(|e| format!("cannot resolve host {host}: {e}"))?
        .collect();
    if addrs.is_empty() {
        return Err(format!("host {host} resolved to no addresses"));
    }
    for addr in &addrs {
        let forbidden = match addr.ip() {
            IpAddr::V4(v4) => is_forbidden_ipv4(&v4),
            IpAddr::V6(v6) => is_forbidden_ipv6(&v6),
        };
        if forbidden {
            return Err(format!("host {host} resolves to forbidden address {}", addr.ip()));
        }
    }
    Ok(())
}

// Same ranges as src/deskagent/deploy.rs:69-88.
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
        // ::ffff:0:0/96 mapped IPv4 — check the embedded v4 address too
        || ip.to_ipv4_mapped().is_some_and(|v4| is_forbidden_ipv4(&v4))
}

/// One chat-completions round trip. `messages` are (role, content) pairs.
/// Blocking HTTP runs off the async runtime via spawn_blocking.
pub async fn chat(messages: Vec<(String, String)>) -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        let url = env::var(ENV_URL).map_err(|_| format!("{ENV_URL} not set"))?;
        let key = env::var(ENV_KEY).map_err(|_| format!("{ENV_KEY} not set"))?;
        let model = env::var(ENV_MODEL).map_err(|_| format!("{ENV_MODEL} not set"))?;

        // SSRF guard runs on every call, not just startup.
        validate_outbound_url(&url)?;

        let body = json!({
            "model": model,
            "messages": messages
                .iter()
                .map(|(role, content)| json!({ "role": role, "content": content }))
                .collect::<Vec<_>>(),
            "temperature": 0.7,
        });

        let endpoint = format!("{}/chat/completions", url.trim_end_matches('/'));
        let resp = ureq::post(&endpoint)
            .set("Authorization", &format!("Bearer {key}"))
            .timeout(REQUEST_TIMEOUT)
            .send_json(body)
            .map_err(|e| format!("AI request failed: {e}"))?;

        let text = resp
            .into_string()
            .map_err(|e| format!("cannot read AI response: {e}"))?;
        let parsed: serde_json::Value =
            serde_json::from_str(&text).map_err(|e| format!("invalid JSON from AI: {e}"))?;
        parsed["choices"][0]["message"]["content"]
            .as_str()
            .map(|s| s.to_string())
            .ok_or_else(|| "AI response missing choices[0].message.content".to_string())
    })
    .await
    .map_err(|e| format!("AI task failed: {e}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_public_literal_ip() {
        // Literal, non-forbidden address: no DNS involved.
        assert!(validate_outbound_url("https://192.0.2.10/v1").is_ok());
    }

    #[test]
    fn rejects_non_http_scheme() {
        assert!(validate_outbound_url("ftp://example.com").is_err());
        assert!(validate_outbound_url("file:///etc/passwd").is_err());
    }

    #[test]
    fn rejects_missing_host() {
        assert!(validate_outbound_url("http:///v1").is_err());
        assert!(validate_outbound_url("not a url").is_err());
    }

    #[test]
    fn rejects_localhost_names() {
        assert!(validate_outbound_url("http://localhost:8080/v1").is_err());
        assert!(validate_outbound_url("http://api.localhost/v1").is_err());
        assert!(validate_outbound_url("http://printer.local/v1").is_err());
    }

    #[test]
    fn rejects_forbidden_ipv4() {
        for host in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.9",
            "192.168.1.5",
            "169.254.3.4",
            "0.1.2.3",
            "100.64.0.1",
        ] {
            assert!(
                validate_outbound_url(&format!("http://{host}/v1")).is_err(),
                "{host} should be rejected"
            );
        }
    }

    #[test]
    fn rejects_forbidden_ipv6() {
        for host in ["[::1]", "[fc00::1]", "[fd12::1]", "[fe80::1]"] {
            assert!(
                validate_outbound_url(&format!("http://{host}/v1")).is_err(),
                "{host} should be rejected"
            );
        }
    }

    #[test]
    fn rejects_ipv4_mapped_ipv6() {
        assert!(validate_outbound_url("http://[::ffff:127.0.0.1]/v1").is_err());
        assert!(validate_outbound_url("http://[::ffff:10.0.0.1]/v1").is_err());
    }

    #[test]
    fn userinfo_is_stripped() {
        // The host after '@' is what matters; it is public so this passes.
        assert!(validate_outbound_url("http://user:pass@192.0.2.10/v1").is_ok());
    }
}

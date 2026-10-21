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

/// AI proxy config read from env or settings.
#[derive(Debug, Clone, Default)]
pub struct AiConfig {
    pub url: String,
    pub key: String,
    pub model: String,
    pub prompt: String,
    /// True only when URL/KEY/MODEL are all set and the URL passes validation.
    pub valid: bool,
    /// Why the bot is disabled, for the startup log or UI.
    pub reason: String,
}

impl AiConfig {
    pub fn new(url: String, key: String, model: String, prompt: String) -> Self {
        if url.is_empty() || key.is_empty() || model.is_empty() {
            return Self {
                url,
                key,
                model,
                prompt,
                valid: false,
                reason: "URL, API Key hoặc Model chưa được cấu hình đầy đủ".to_string(),
            };
        }
        match validate_outbound_url(&url) {
            Ok(()) => Self {
                url,
                key,
                model,
                prompt,
                valid: true,
                reason: String::new(),
            },
            Err(e) => Self {
                url,
                key,
                model,
                prompt,
                valid: false,
                reason: e,
            },
        }
    }

    /// Read env vars and validate the URL once at startup. Invalid config
    /// disables the bot (it replies "chưa cấu hình AI"); the server still runs.
    pub fn from_env() -> Self {
        let url = env::var(ENV_URL).unwrap_or_default();
        let key = env::var(ENV_KEY).unwrap_or_default();
        let model = env::var(ENV_MODEL).unwrap_or_default();
        Self::new(url, key, model, String::new())
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
/// Outbound requests use `safe_resolve` on ureq::Agent to eliminate DNS rebinding (TOCTOU).
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
    if host == "localhost"
        || host.ends_with(".localhost")
        || host.ends_with(".local")
        || host.ends_with(".internal")
        || host.ends_with(".lan")
        || host.ends_with(".home.arpa")
    {
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

/// Custom DNS resolver for ureq to prevent SSRF and DNS rebinding (TOCTOU).
/// Resolves socket addresses and verifies every resolved IP address before returning to ureq.
pub fn safe_resolve(netloc: &str) -> std::io::Result<Vec<SocketAddr>> {
    let mut host_str = netloc;
    if let Some(at) = host_str.rfind('@') {
        host_str = &host_str[at + 1..];
    }

    let raw_host = if let Some(stripped) = host_str.strip_prefix('[') {
        let close = stripped.find(']').ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "unclosed IPv6 literal in netloc")
        })?;
        &stripped[..close]
    } else if let Some((h, _)) = host_str.rsplit_once(':') {
        h
    } else {
        host_str
    };

    let host = raw_host.trim_end_matches('.').to_lowercase();
    if host.is_empty() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "empty host in netloc",
        ));
    }

    if host == "localhost"
        || host.ends_with(".localhost")
        || host.ends_with(".local")
        || host.ends_with(".internal")
        || host.ends_with(".lan")
        || host.ends_with(".home.arpa")
    {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            format!("SSRF blocked: host '{host}' is forbidden"),
        ));
    }

    if let Ok(list) = env::var(ENV_HOSTS) {
        let allowed: Vec<&str> = list.split(',').map(str::trim).filter(|s| !s.is_empty()).collect();
        if !allowed.is_empty() && !allowed.iter().any(|a| a.eq_ignore_ascii_case(&host)) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                format!("SSRF blocked: host '{host}' is not in {ENV_HOSTS} allowlist"),
            ));
        }
    }

    if let Ok(ip4) = host.parse::<Ipv4Addr>() {
        if is_forbidden_ipv4(&ip4) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                format!("SSRF blocked: forbidden literal IPv4 '{ip4}'"),
            ));
        }
    }
    if let Ok(ip6) = host.parse::<Ipv6Addr>() {
        if is_forbidden_ipv6(&ip6) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                format!("SSRF blocked: forbidden literal IPv6 '{ip6}'"),
            ));
        }
    }

    let addrs: Vec<SocketAddr> = netloc
        .to_socket_addrs()
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, format!("cannot resolve '{netloc}': {e}")))?
        .collect();

    if addrs.is_empty() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("host '{host}' resolved to no addresses"),
        ));
    }

    for addr in &addrs {
        let forbidden = match addr.ip() {
            IpAddr::V4(v4) => is_forbidden_ipv4(&v4),
            IpAddr::V6(v6) => is_forbidden_ipv6(&v6),
        };
        if forbidden {
            return Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                format!("SSRF/DNS-rebinding blocked: resolved forbidden address {}", addr.ip()),
            ));
        }
    }

    Ok(addrs)
}

fn is_forbidden_ipv4(ip: &Ipv4Addr) -> bool {
    let o = ip.octets();
    // 127.0.0.0/8, 10/8, 172.16/12, 192.168/16, 169.254/16
    ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_multicast()
        || ip.is_broadcast()
        // 0.0.0.0/8
        || o[0] == 0
        // 100.64.0.0/10 (carrier-grade NAT)
        || (o[0] == 100 && (64..=127).contains(&o[1]))
        // 198.18.0.0/15 (benchmarking)
        || (o[0] == 198 && (18..=19).contains(&o[1]))
        // 240.0.0.0/4 (reserved / Class E)
        || o[0] >= 240
}

fn is_forbidden_ipv6(ip: &Ipv6Addr) -> bool {
    let seg = ip.segments();
    ip.is_unspecified() // ::
        || ip.is_loopback() // ::1
        || ip.is_multicast() // ff00::/8
        // fc00::/7 (unique local)
        || (seg[0] & 0xFE00) == 0xFC00
        // fe80::/10 (link local)
        || (seg[0] & 0xFFC0) == 0xFE80
        // ::ffff:0:0/96 mapped IPv4 — check the embedded v4 address too
        || ip.to_ipv4_mapped().is_some_and(|v4| is_forbidden_ipv4(&v4))
        // ::x.x.x.x IPv4-compatible
        || (seg[0] == 0
            && seg[1] == 0
            && seg[2] == 0
            && seg[3] == 0
            && seg[4] == 0
            && seg[5] == 0
            && {
                let v4 = Ipv4Addr::new(
                    (seg[6] >> 8) as u8,
                    seg[6] as u8,
                    (seg[7] >> 8) as u8,
                    seg[7] as u8,
                );
                is_forbidden_ipv4(&v4)
            })
}

/// One chat-completions round trip with custom config. `messages` are (role, content) pairs.
/// Blocking HTTP runs off the async runtime via spawn_blocking.
pub async fn chat_with_config(
    config: AiConfig,
    messages: Vec<(String, String)>,
) -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        let url = config.url;
        let key = config.key;
        let model = config.model;

        if url.is_empty() || key.is_empty() || model.is_empty() {
            return Err("AI chưa được cấu hình (thiếu URL, API Key hoặc Model)".to_string());
        }

        // SSRF guard runs on every call, not just startup.
        validate_outbound_url(&url)?;

        let mut msgs_payload = Vec::new();
        if !config.prompt.is_empty() {
            msgs_payload.push(json!({ "role": "system", "content": config.prompt }));
        }
        for (role, content) in &messages {
            msgs_payload.push(json!({ "role": role, "content": content }));
        }

        let body = json!({
            "model": model,
            "messages": msgs_payload,
            "temperature": 0.7,
        });

        let endpoint = if url.ends_with("/chat/completions") {
            url
        } else {
            format!("{}/chat/completions", url.trim_end_matches('/'))
        };

        let agent = ureq::builder()
            .redirects(0)
            .timeout(REQUEST_TIMEOUT)
            .resolver(safe_resolve)
            .build();

        let resp = agent
            .post(&endpoint)
            .set("Authorization", &format!("Bearer {key}"))
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

#[allow(dead_code)]
pub async fn chat(messages: Vec<(String, String)>) -> Result<String, String> {
    chat_with_config(AiConfig::from_env(), messages).await
}

pub async fn test_ai(config: AiConfig) -> Result<String, String> {
    let test_msgs = vec![(
        "user".to_string(),
        "DeskAgent ping test. Trả lời đúng 1 câu ngắn: OK đã kết nối DeskAgent AI thành công.".to_string(),
    )];
    chat_with_config(config, test_msgs).await
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
        for host in ["[::]", "[::1]", "[fc00::1]", "[fd12::1]", "[fe80::1]"] {
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

    #[test]
    fn safe_resolve_blocks_forbidden_destinations() {
        for target in [
            "localhost:80",
            "foo.localhost:80",
            "service.local:80",
            "api.internal:80",
            "router.lan:80",
            "127.0.0.1:80",
            "10.0.0.1:80",
            "172.16.0.1:80",
            "192.168.1.1:80",
            "169.254.1.1:80",
            "0.0.0.0:80",
            "100.64.0.1:80",
            "224.0.0.1:80",
            "240.0.0.1:80",
            "[::1]:80",
            "[::]:80",
            "[::ffff:127.0.0.1]:80",
            "[fc00::1]:80",
            "[fe80::1]:80",
        ] {
            assert!(
                safe_resolve(target).is_err(),
                "{target} should be blocked by safe_resolve"
            );
        }
    }

    #[test]
    fn safe_resolve_accepts_public_ip() {
        let res = safe_resolve("192.0.2.10:80");
        assert!(res.is_ok());
        let addrs = res.unwrap();
        assert_eq!(addrs.len(), 1);
        assert_eq!(addrs[0].to_string(), "192.0.2.10:80");
    }
}

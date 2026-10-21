//! Authentication for the manager API.
//!
//! [Note]
//! Two credentials guard the API. The admin token authorises the console
//! and the job dispatch; it comes from the environment and the admin API
//! stays closed when it is missing, so an operator who forgot to set it
//! gets a refusal rather than an open door. The device token authorises
//! one client: it is issued once at registration, only its hash is stored
//! and it is sent back in the `X-Device-Token` header.

use axum::http::{HeaderMap, StatusCode};
use sha2::{Digest, Sha256};

/// Header carrying the admin token.
const ADMIN_HEADER: &str = "x-admin-token";
/// Header carrying the device token.
const DEVICE_HEADER: &str = "x-device-token";

/// The admin credential of the manager API.
pub struct AdminAuth {
    token: Option<String>,
}

impl AdminAuth {
    /// Read the admin token from `DESKAGENT_MANAGER_ADMIN_TOKEN`.
    pub fn from_env() -> Self {
        let token = std::env::var("DESKAGENT_MANAGER_ADMIN_TOKEN")
            .ok()
            .map(|t| t.trim().to_owned())
            .filter(|t| !t.is_empty());
        Self { token }
    }

    /// Whether the admin API can be used at all.
    pub fn is_enabled(&self) -> bool {
        self.token.is_some()
    }

    /// Authorise an admin request.
    pub fn authorize(&self, headers: &HeaderMap) -> Result<(), (StatusCode, String)> {
        let expected = match &self.token {
            Some(t) => t,
            None => {
                return Err((
                    StatusCode::FORBIDDEN,
                    "the admin api is disabled: set DESKAGENT_MANAGER_ADMIN_TOKEN".to_string(),
                ))
            }
        };
        let given = header(headers, ADMIN_HEADER);
        if constant_time_eq(given.as_bytes(), expected.as_bytes()) {
            Ok(())
        } else {
            Err((StatusCode::UNAUTHORIZED, "invalid admin token".to_string()))
        }
    }
}

/// The value of a header as a string, empty when it is absent.
pub fn header<'a>(headers: &'a HeaderMap, name: &str) -> &'a str {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
}

/// The device token of a request.
pub fn device_token(headers: &HeaderMap) -> &str {
    header(headers, DEVICE_HEADER)
}

/// Hash a token for storage; the clear text is never written to the database.
pub fn hash_token(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Compare two byte strings without leaking where they differ.
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// Whether a presented device token matches the stored hash.
pub fn token_matches(presented: &str, stored_hash: &str) -> bool {
    !stored_hash.is_empty()
        && constant_time_eq(hash_token(presented).as_bytes(), stored_hash.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_hash_is_stable_and_hides_the_token() {
        let hash = hash_token("s3cret");
        assert_eq!(hash.len(), 64);
        assert_eq!(hash, hash_token("s3cret"));
        assert!(!hash.contains("s3cret"));
        assert_ne!(hash, hash_token("s3cret2"));
    }

    #[test]
    fn a_token_matches_only_its_own_hash() {
        let hash = hash_token("s3cret");
        assert!(token_matches("s3cret", &hash));
        assert!(!token_matches("wrong", &hash));
        assert!(!token_matches("", &hash));
        // An empty stored hash never authorises, even an empty token.
        assert!(!token_matches("", ""));
    }

    #[test]
    fn the_admin_api_is_closed_without_a_configured_token() {
        let auth = AdminAuth { token: None };
        assert!(!auth.is_enabled());
        let err = auth.authorize(&HeaderMap::new()).unwrap_err();
        assert_eq!(err.0, StatusCode::FORBIDDEN);
    }

    #[test]
    fn the_admin_api_refuses_a_wrong_token() {
        let auth = AdminAuth {
            token: Some("right".to_string()),
        };
        assert!(auth.is_enabled());
        let mut headers = HeaderMap::new();
        headers.insert(ADMIN_HEADER, "wrong".parse().unwrap());
        assert_eq!(
            auth.authorize(&headers).unwrap_err().0,
            StatusCode::UNAUTHORIZED
        );
        headers.insert(ADMIN_HEADER, "right".parse().unwrap());
        assert!(auth.authorize(&headers).is_ok());
        // No header at all is refused as well.
        assert_eq!(
            auth.authorize(&HeaderMap::new()).unwrap_err().0,
            StatusCode::UNAUTHORIZED
        );
    }
}

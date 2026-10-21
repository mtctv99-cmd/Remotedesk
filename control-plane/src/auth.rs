// Authentication primitives for the control plane.
//
// Schemes are byte-identical to manager/src/crypto.rs so both services accept
// the same credentials against the same tables:
// - tokens: 16 CSPRNG bytes, hex (admin tokens carry a `tok_` prefix, device
//   tokens are bare hex — same as manager routes::new_id);
// - at rest: base64(SHA-256(token)) — a DB leak yields no usable credential;
// - Ed25519 verify via ring (same curve manager signs deploy jobs with).
//
// v2 PeerId signature layout (NORMATIVE — the future client signer must build
// exactly this; the server rejects anything else):
//   msg = AUTH_DOMAIN || version_be32 || peer_id_utf8 || device_uuid_raw || issued_at_be32
// where AUTH_DOMAIN = b"deskagent-sig/2/kx-params" (same constant as
// src/rendezvous_mediator.rs module `v2::AUTH_DOMAIN`). Freshness window
// +-REGISTER_FRESHNESS_SECS around now; KX floor enforced by signaling.

use base64::{engine::general_purpose::STANDARD, Engine as _};

/// Domain separator for every v2 signature. Separate from v1's `rdkx-params`:
/// a v2 signature must never verify as v1 material and vice versa.
pub const AUTH_DOMAIN: &[u8] = b"deskagent-sig/2/kx-params";

/// Freshness window for RegisterRequest identity timestamps (seconds).
pub const REGISTER_FRESHNESS_SECS: i64 = 300;

/// Lowest KX generation a v2 endpoint negotiates (mirrors
/// rendezvous_mediator::v2::KX_VERSION_MIN; duplicated here so the service
/// builds without the client crate).
pub const KX_VERSION_MIN: u32 = 2;

/// 16 CSPRNG bytes as lowercase hex (32 chars).
pub fn random_hex() -> Result<String, String> {
    use ring::rand::{SecureRandom, SystemRandom};
    let rng = SystemRandom::new();
    let mut bytes = [0u8; 16];
    rng.fill(&mut bytes).map_err(|_| "CSPRNG failure".to_string())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

/// base64(SHA-256(token)) — identical to manager crypto::hash_token.
pub fn hash_token(token: &str) -> String {
    use ring::digest::{digest, SHA256};
    STANDARD.encode(digest(&SHA256, token.as_bytes()).as_ref())
}

/// Build the exact byte string a PeerId signature covers.
pub fn peer_id_message(
    version: u32,
    peer_id: &str,
    device_uuid: &[u8],
    issued_at: u32,
) -> Vec<u8> {
    let mut m = Vec::with_capacity(
        AUTH_DOMAIN.len() + 4 + peer_id.len() + device_uuid.len() + 4,
    );
    m.extend_from_slice(AUTH_DOMAIN);
    m.extend_from_slice(&version.to_be_bytes());
    m.extend_from_slice(peer_id.as_bytes());
    m.extend_from_slice(device_uuid);
    m.extend_from_slice(&issued_at.to_be_bytes());
    m
}

/// Verify an Ed25519 PeerId signature. Returns Ok(()) only when the key,
/// layout, version floor and freshness window all check out.
pub fn verify_peer_id(
    version: u32,
    peer_id: &str,
    ed25519_pubkey: &[u8],
    device_uuid: &[u8],
    issued_at: u32,
    kx_version: u32,
    signature: &[u8],
    now_secs: i64,
) -> Result<(), String> {
    if version != 2 {
        return Err("unsupported protocol version (floor: 2)".to_string());
    }
    if kx_version < KX_VERSION_MIN {
        return Err(format!(
            "kx version {kx_version} below v2 floor {KX_VERSION_MIN}"
        ));
    }
    if peer_id.is_empty() || peer_id.len() > 64 {
        return Err("peer id length out of range".to_string());
    }
    if device_uuid.len() != 16 {
        return Err("device uuid must be 16 bytes".to_string());
    }
    let age = now_secs - issued_at as i64;
    if age.abs() > REGISTER_FRESHNESS_SECS {
        return Err("identity timestamp outside freshness window".to_string());
    }
    let msg = peer_id_message(version, peer_id, device_uuid, issued_at);
    let peer_pub =
        ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, ed25519_pubkey);
    peer_pub
        .verify(&msg, signature)
        .map_err(|_| "ed25519 signature invalid".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ring::signature::{Ed25519KeyPair, KeyPair};

    fn keypair() -> Ed25519KeyPair {
        let rng = ring::rand::SystemRandom::new();
        let pkcs8 = Ed25519KeyPair::generate_pkcs8(&rng).unwrap();
        Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap()
    }

    #[test]
    fn peer_id_roundtrip_and_cross_domain_reject() {
        let kp = keypair();
        let uuid = [7u8; 16];
        let now = 1_800_000_000i64;
        let issued = now as u32;
        let msg = peer_id_message(2, "123456789", &uuid, issued);
        let sig = kp.sign(&msg);
        verify_peer_id(
            2,
            "123456789",
            kp.public_key().as_ref(),
            &uuid,
            issued,
            2,
            sig.as_ref(),
            now,
        )
        .unwrap();
        // v1 domain message must NOT verify here (wrong layout/domain).
        let v1ish = b"rdkx-params123456789".to_vec();
        let bad = kp.sign(&v1ish);
        assert!(verify_peer_id(
            2,
            "123456789",
            kp.public_key().as_ref(),
            &uuid,
            issued,
            2,
            bad.as_ref(),
            now
        )
        .is_err());
        // Stale timestamp rejected.
        assert!(verify_peer_id(
            2,
            "123456789",
            kp.public_key().as_ref(),
            &uuid,
            issued - 3600,
            2,
            sig.as_ref(),
            now
        )
        .is_err());
        // KX below floor rejected.
        assert!(verify_peer_id(
            2,
            "123456789",
            kp.public_key().as_ref(),
            &uuid,
            issued,
            1,
            sig.as_ref(),
            now
        )
        .is_err());
    }
}

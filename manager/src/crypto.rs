use base64::{engine::general_purpose::STANDARD, Engine as _};
use ring::signature::{Ed25519KeyPair, KeyPair};

/// Sign a deploy job with the server's Ed25519 private key seed.
/// Payload format: "{job_id}:{client_id}:{package_url}:{package_path}:{silent_cmd}".
///
/// [Note]
/// `package_path` is covered by the signature: the client uses it to pick the
/// file to execute and the working directory of the silent command, so it must
/// not be editable independently of the signature (mirror of
/// src/deskagent/deploy.rs verify_job_signature).
pub fn sign_deploy_payload(
    private_key_b64: &str,
    job_id: &str,
    client_id: &str,
    package_url: &str,
    package_path: &str,
    silent_cmd: &str,
) -> Result<String, String> {
    let bytes = STANDARD
        .decode(private_key_b64.trim())
        .map_err(|e| format!("decode private key failed: {e}"))?;
    if bytes.len() < 32 {
        return Err("private key must be at least 32 bytes".to_string());
    }
    let seed = &bytes[0..32];
    let keypair =
        Ed25519KeyPair::from_seed_unchecked(seed).map_err(|e| format!("invalid ed25519 seed: {e}"))?;
    let payload = format!("{job_id}:{client_id}:{package_url}:{package_path}:{silent_cmd}");
    let sig = keypair.sign(payload.as_bytes());
    Ok(STANDARD.encode(sig.as_ref()))
}

/// Derive the Ed25519 public key (base64) matching a private key seed (base64).
pub fn derive_public_key(private_key_b64: &str) -> Result<String, String> {
    let bytes = STANDARD
        .decode(private_key_b64.trim())
        .map_err(|e| format!("decode private key failed: {e}"))?;
    if bytes.len() < 32 {
        return Err("private key must be at least 32 bytes".to_string());
    }
    let keypair = Ed25519KeyPair::from_seed_unchecked(&bytes[0..32])
        .map_err(|e| format!("invalid ed25519 seed: {e}"))?;
    Ok(STANDARD.encode(keypair.public_key().as_ref()))
}

/// Generate a fresh random Ed25519 private key seed (base64).
pub fn generate_private_key() -> Result<String, String> {
    use ring::rand::{SecureRandom, SystemRandom};
    let rng = SystemRandom::new();
    let mut seed = [0u8; 32];
    rng.fill(&mut seed)
        .map_err(|_| "CSPRNG failed to generate the server key seed".to_string())?;
    Ok(STANDARD.encode(seed))
}

/// Canonical payload a version-manifest signature covers: newline-joined
/// so URLs (which contain ':') cannot shift fields. Trim inputs before
/// sign/verify (settings values are trimmed on save).
pub fn version_manifest_payload(latest: &str, min_supported: &str, url: &str, sha256: &str) -> String {
    format!("{}\n{}\n{}\n{}", latest.trim(), min_supported.trim(), url.trim(), sha256.trim())
}

/// Sign a version manifest with the server Ed25519 seed (same key that
/// publishes settings.server_key, so the enroll trust anchor verifies it).
pub fn sign_version_manifest(
    private_key_b64: &str,
    latest: &str,
    min_supported: &str,
    url: &str,
    sha256: &str,
) -> Result<String, String> {
    let bytes = STANDARD.decode(private_key_b64.trim()).map_err(|e| format!("decode private key failed: {e}"))?;
    if bytes.len() < 32 {
        return Err("private key must be at least 32 bytes".to_string());
    }
    let keypair =
        Ed25519KeyPair::from_seed_unchecked(&bytes[0..32]).map_err(|e| format!("invalid ed25519 seed: {e}"))?;
    Ok(STANDARD.encode(keypair.sign(version_manifest_payload(latest, min_supported, url, sha256).as_bytes()).as_ref()))
}

/// Verify a version-manifest signature against a base64 Ed25519 pubkey
/// (settings.server_key / staged v2-server-key anchor).
pub fn verify_version_manifest(
    public_key_b64: &str,
    latest: &str,
    min_supported: &str,
    url: &str,
    sha256: &str,
    signature_b64: &str,
) -> Result<(), String> {
    use ring::signature::UnparsedPublicKey;
    let pub_bytes = STANDARD.decode(public_key_b64.trim()).map_err(|e| format!("decode public key failed: {e}"))?;
    let sig_bytes = STANDARD.decode(signature_b64.trim()).map_err(|e| format!("decode signature failed: {e}"))?;
    let peer = UnparsedPublicKey::new(&ring::signature::ED25519, pub_bytes);
    peer.verify(
        version_manifest_payload(latest, min_supported, url, sha256).as_bytes(),
        &sig_bytes,
    )
    .map_err(|_| "version manifest signature mismatch".to_string())
}

/// SHA-256 of a device token (base64), for at-rest storage: the plaintext
/// token is shown once at register and never persisted.
pub fn hash_token(token: &str) -> String {
    use ring::digest::{digest, SHA256};
    STANDARD.encode(digest(&SHA256, token.as_bytes()).as_ref())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ring::signature::UnparsedPublicKey;

    #[test]
    fn test_sign_and_verify_ed25519() {
        let priv_b64 = "pgI8dyjiH3mUe9hgStezwAKaHZMkBMlqM3Ii+/qVjKJGzHPpxT6GOtRQMmO0nsGPyp116b0WNhWsPD62HvKMoQ==";
        let pub_b64 = "Rsxz6cU+hjrUUDJjtJ7Bj8qddem9FjYVrDw+th7yjKE=";

        let sig_b64 = sign_deploy_payload(
            priv_b64,
            "j123",
            "client_456",
            "https://example.com/pkg.msi",
            "C:\\pkg\\setup.msi",
            "msiexec /qn",
        )
        .unwrap();
        assert!(!sig_b64.is_empty());

        let pub_bytes = STANDARD.decode(pub_b64).unwrap();
        let sig_bytes = STANDARD.decode(sig_b64).unwrap();
        let payload = "j123:client_456:https://example.com/pkg.msi:C:\\pkg\\setup.msi:msiexec /qn";

        let peer_pub = UnparsedPublicKey::new(&ring::signature::ED25519, &pub_bytes);
        assert!(peer_pub.verify(payload.as_bytes(), &sig_bytes).is_ok());

        // Tampered payload fails
        let tampered = "j123:client_456:https://example.com/pkg.msi:C:\\pkg\\setup.msi:calc.exe";
        assert!(peer_pub.verify(tampered.as_bytes(), &sig_bytes).is_err());

        // Tampered package_url fails
        let tampered_url = "j123:client_456:https://evil.com/pkg.msi:C:\\pkg\\setup.msi:msiexec /qn";
        assert!(peer_pub.verify(tampered_url.as_bytes(), &sig_bytes).is_err());

        // Tampered package_path fails
        let tampered_path = "j123:client_456:https://example.com/pkg.msi:C:\\evil:msiexec /qn";
        assert!(peer_pub.verify(tampered_path.as_bytes(), &sig_bytes).is_err());
    }

    #[test]
    fn test_version_manifest_sign_verify_roundtrip_and_tamper() {
        let priv_b64 = "pgI8dyjiH3mUe9hgStezwAKaHZMkBMlqM3Ii+/qVjKJGzHPpxT6GOtRQMmO0nsGPyp116b0WNhWsPD62HvKMoQ==";
        let pub_b64 = "Rsxz6cU+hjrUUDJjtJ7Bj8qddem9FjYVrDw+th7yjKE=";
        let sig = sign_version_manifest(
            priv_b64,
            "1.5.1",
            "1.5.0",
            "https://example.invalid/dl",
            "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        )
        .unwrap();
        verify_version_manifest(
            pub_b64,
            "1.5.1",
            "1.5.0",
            "https://example.invalid/dl",
            "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            &sig,
        )
        .unwrap();
        // Tampered URL fails.
        assert!(verify_version_manifest(
            pub_b64,
            "1.5.1",
            "1.5.0",
            "https://evil.invalid/dl",
            "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            &sig,
        )
        .is_err());
        // Empty signature fails.
        assert!(verify_version_manifest(
            pub_b64, "1.5.1", "1.5.0", "https://example.invalid/dl",
            "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", "",
        )
        .is_err());
    }

    #[test]
    fn test_derive_public_key_matches_expected() {
        let priv_b64 = "pgI8dyjiH3mUe9hgStezwAKaHZMkBMlqM3Ii+/qVjKJGzHPpxT6GOtRQMmO0nsGPyp116b0WNhWsPD62HvKMoQ==";
        let pub_b64 = derive_public_key(priv_b64).unwrap();
        assert_eq!(pub_b64, "Rsxz6cU+hjrUUDJjtJ7Bj8qddem9FjYVrDw+th7yjKE=");
    }
}

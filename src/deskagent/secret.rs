//! Storage for the DeskAgent client secrets that must not sit on disk in
//! clear text.
//!
//! [Note]
//! The Manager device token authorizes inventory upload and remote job
//! execution on this client, so a leaked token is a remote-code-execution
//! primitive. On Windows the token is sealed with the Data Protection
//! API, which binds the blob to the logged-on user and the machine;
//! elsewhere it is stored readable by its owner only.

use std::path::Path;

/// Read a secret from `path`.
///
/// [Note]
/// Returns `None` when the file is missing, unreadable or cannot be
/// unsealed, so a secret written before this protection existed is
/// treated as absent and re-issued instead of being trusted.
pub fn read_secret(path: &Path) -> Option<String> {
    let raw = std::fs::read(path).ok()?;
    let plain = unseal(&raw)?;
    let text = String::from_utf8(plain).ok()?;
    Some(text.trim().to_owned())
}

/// Write a secret to `path`, sealed so only this user can read it.
///
/// [Note]
/// Fails instead of falling back to clear text: a secret that cannot be
/// protected must not be stored.
pub fn write_secret(path: &Path, value: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let sealed = seal(value.as_bytes())
        .ok_or_else(|| std::io::Error::other("failed to seal the secret for this user"))?;
    std::fs::write(path, sealed)?;
    restrict_to_owner(path)
}

#[cfg(target_os = "windows")]
fn seal(plain: &[u8]) -> Option<Vec<u8>> {
    use winapi::um::dpapi::{CryptProtectData, CRYPTPROTECT_UI_FORBIDDEN};
    use winapi::um::wincrypt::DATA_BLOB;

    let mut input = DATA_BLOB {
        cbData: plain.len() as _,
        pbData: plain.as_ptr() as *mut _,
    };
    let mut output: DATA_BLOB = unsafe { std::mem::zeroed() };
    // SAFETY: `input` borrows `plain` for the duration of the call,
    // `output` is a zeroed blob the callee fills in, and
    // `CRYPTPROTECT_UI_FORBIDDEN` keeps the call non-interactive.
    let ok = unsafe {
        CryptProtectData(
            &mut input,
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        )
    };
    if ok == 0 {
        return None;
    }
    // SAFETY: on success the callee allocated `output.pbData` with
    // `output.cbData` readable bytes.
    let sealed =
        unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize) }.to_vec();
    // SAFETY: `output.pbData` came from `LocalAlloc` inside DPAPI.
    unsafe {
        winapi::um::winbase::LocalFree(output.pbData as _);
    }
    Some(sealed)
}

#[cfg(target_os = "windows")]
fn unseal(sealed: &[u8]) -> Option<Vec<u8>> {
    use winapi::um::dpapi::{CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN};
    use winapi::um::wincrypt::DATA_BLOB;

    let mut input = DATA_BLOB {
        cbData: sealed.len() as _,
        pbData: sealed.as_ptr() as *mut _,
    };
    let mut output: DATA_BLOB = unsafe { std::mem::zeroed() };
    // SAFETY: `input` borrows `sealed` for the duration of the call and
    // `output` is a zeroed blob the callee fills in.
    let ok = unsafe {
        CryptUnprotectData(
            &mut input,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        )
    };
    if ok == 0 {
        return None;
    }
    // SAFETY: on success the callee allocated `output.pbData` with
    // `output.cbData` readable bytes.
    let plain =
        unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize) }.to_vec();
    // SAFETY: `output.pbData` came from `LocalAlloc` inside DPAPI.
    unsafe {
        winapi::um::winbase::LocalFree(output.pbData as _);
    }
    Some(plain)
}

#[cfg(not(target_os = "windows"))]
fn seal(plain: &[u8]) -> Option<Vec<u8>> {
    Some(plain.to_vec())
}

#[cfg(not(target_os = "windows"))]
fn unseal(sealed: &[u8]) -> Option<Vec<u8>> {
    Some(sealed.to_vec())
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
}

/// Windows relies on DPAPI for the confidentiality of the secret: the
/// blob is bound to the logged-on user, so another account cannot
/// decrypt it even with read access to the file.
#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secret_round_trips_through_the_store() {
        let dir = std::env::temp_dir().join(format!("deskagent-secret-{}", std::process::id()));
        let path = dir.join("token");
        std::fs::create_dir_all(&dir).unwrap();
        write_secret(&path, "s3cret-token").unwrap();
        assert_eq!(read_secret(&path).as_deref(), Some("s3cret-token"));
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A blob that DPAPI cannot decrypt is reported as absent, so a secret
    /// written before this protection existed is re-issued rather than
    /// trusted.
    #[cfg(target_os = "windows")]
    #[test]
    fn an_unreadable_secret_is_reported_as_absent() {
        let dir = std::env::temp_dir().join(format!("deskagent-secret-bad-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("token");
        std::fs::write(&path, b"not a sealed blob").unwrap();
        assert_eq!(read_secret(&path), None);
        std::fs::remove_dir_all(&dir).ok();
    }
}

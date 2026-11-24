/// DeskAgent extension modules on top of the upstream RustDesk client.
///
/// [Note]
/// `system_info` collects host inventory and Windows event logs via
/// powershell/wevtutil, and `deploy` runs a blocking daemon that polls
/// the local Manager for deploy jobs. Call [`start_background`] once to
/// launch that daemon; the only upstream wiring is `pub mod deskagent;`
/// in src/lib.rs.
pub mod ai_chat;
pub mod deploy;
pub mod secret;
pub mod system_info;

use hbb_common::log;
use std::sync::Once;
use std::time::Duration;

/// Daemon poll interval in seconds.
const DAEMON_INTERVAL_SECS: u64 = 30;

/// One-time viewer defaults tuned for smooth sessions.
///
/// [Note]
/// Only fills options the user has never set (empty user-default), so
/// explicit user choices always win. "auto" codec preference lets the
/// encoder pick the hardware codec (h264/h265) when both sides support it,
/// which is the biggest single latency lever on local networks.
fn apply_smooth_defaults() {
    const RECOMMENDED: [(&str, &str); 1] = [("codec-preference", "auto")];
    for (key, value) in RECOMMENDED {
        if hbb_common::config::UserDefaultConfig::load().get(key).is_empty() {
            let mut cfg = hbb_common::config::UserDefaultConfig::load();
            cfg.set(key.to_owned(), value.to_owned());
        }
    }
}

/// Whether this process should host the daemon.
///
/// [Note]
/// `core_main` runs in every role (service, `--server`, `--tray`, GUI), so
/// starting the daemon unconditionally makes several processes register,
/// upload and execute the same deploy jobs. Keep it to one process that has
/// the right privileges: the Windows service when it is installed, otherwise
/// the GUI process (the `--tray` and `--server` companions would only
/// duplicate its work). Other platforms have a single long-lived process.
fn should_start_daemon() -> bool {
    // Every role may host the daemon; a process-wide named mutex below keeps
    // exactly one of GUI / --tray / --server doing the work. The old role
    // filter meant a headless tray+server install never checked for updates.
    true
}

#[cfg(target_os = "windows")]
fn acquire_daemon_mutex() -> bool {
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::synchapi::CreateMutexW;

    static HANDLE: std::sync::Mutex<Option<isize>> = std::sync::Mutex::new(None);
    let name: Vec<u16> = "Global\\DeskAgentDaemon\0".encode_utf16().collect();
    unsafe {
        let h = CreateMutexW(std::ptr::null_mut(), 0, name.as_ptr());
        if h.is_null() {
            return false;
        }
        if std::io::Error::last_os_error().raw_os_error() == Some(183) {
            // ERROR_ALREADY_EXISTS: another process owns the daemon.
            CloseHandle(h);
            return false;
        }
        if let Ok(mut slot) = HANDLE.lock() {
            *slot = Some(h as isize);
        }
        true
    }
}

/// Start the background DeskAgent daemon (no-op after the first call).
///
/// [Note]
/// `Once` guarantees a single daemon thread per process. The thread
/// never propagates errors or panics: each failing tick is logged and
/// the loop keeps running.
pub fn start_background() {
    static START: Once = Once::new();
    START.call_once(|| {
        apply_smooth_defaults();
        if !should_start_daemon() {
            log::debug!("deskagent daemon not started in this process role");
            return;
        }
        #[cfg(target_os = "windows")]
        if !acquire_daemon_mutex() {
            log::debug!("deskagent daemon already hosted by another process");
            return;
        }
        let spawned = std::thread::Builder::new()
            .name("deskagent-daemon".to_owned())
            .spawn(|| loop {
                // A failing or panicking tick must never kill the daemon.
                match std::panic::catch_unwind(deploy::tick) {
                    Ok(Ok(())) => {}
                    Ok(Err(e)) => log::warn!("deskagent daemon tick failed: {}", e),
                    Err(_) => log::warn!("deskagent daemon tick panicked; retrying"),
                }
                std::thread::sleep(Duration::from_secs(DAEMON_INTERVAL_SECS));
            });
        if let Err(e) = spawned {
            log::warn!("failed to spawn the deskagent daemon thread: {}", e);
        }
    });
}

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

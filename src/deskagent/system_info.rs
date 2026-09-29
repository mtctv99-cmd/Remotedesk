use hbb_common::{bail, log, ResultType};
use serde_derive::{Deserialize, Serialize};
use std::process::Command;

/// Basic host information collected by DeskAgent.
#[derive(Debug, PartialEq, Default, Serialize, Deserialize, Clone)]
pub struct SystemInfo {
    #[serde(default)]
    pub hostname: String,
    #[serde(default)]
    pub os: String,
    #[serde(default)]
    pub os_version: String,
    #[serde(default)]
    pub arch: String,
}

/// One-shot powershell script rendering the full host inventory as JSON.
///
/// [Note]
/// A single powershell process: one Get-CimInstance per class, a small
/// Select-Object per class, then one ConvertTo-Json. `Name` on
/// Win32_ComputerSystem provides the hostname used by [`collect`].
const INFO_SCRIPT: &str = r#"
$ErrorActionPreference = 'Stop'
$computer_system = Get-CimInstance Win32_ComputerSystem |
    Select-Object Name,Manufacturer,Model,TotalPhysicalMemory
$operating_system = Get-CimInstance Win32_OperatingSystem |
    Select-Object Caption,Version,BuildNumber
$processor = Get-CimInstance Win32_Processor |
    Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
$video_controller = Get-CimInstance Win32_VideoController |
    Select-Object Name,AdapterRAM,DriverVersion
$disk_drive = Get-CimInstance Win32_DiskDrive |
    Select-Object Model,Size
$logical_disk = Get-CimInstance Win32_LogicalDisk |
    Select-Object DeviceID,VolumeName,Size,FreeSpace
[ordered]@{
    computer_system = $computer_system
    operating_system = $operating_system
    processor = $processor
    video_controller = $video_controller
    disk_drive = $disk_drive
    logical_disk = $logical_disk
} | ConvertTo-Json -Depth 4
"#;

/// Collect host information for the DeskAgent deployment record.
///
/// [Note]
/// Tries the real powershell inventory first; falls back to build-time
/// constants (empty hostname) when powershell is unavailable or its
/// output is unusable. Never returns `Err`.
pub fn collect() -> ResultType<SystemInfo> {
    // collect_system_info never returns Err; errors arrive as JSON.
    Ok(system_info_from_inventory(&collect_system_info()?))
}

/// Collect the full host inventory as a JSON string.
///
/// [Note]
/// Never fails with `Err`: a failed or unparsable powershell run is
/// logged and reported as `{"error": "..."}` so the deploy daemon keeps
/// running and the Manager can see why the inventory is missing.
pub fn collect_system_info() -> ResultType<String> {
    match run_powershell(INFO_SCRIPT) {
        Ok(stdout) => {
            if serde_json::from_str::<serde_json::Value>(&stdout).is_ok() {
                Ok(stdout)
            } else {
                log::warn!("system inventory output is not valid JSON");
                Ok(serde_json::json!({ "error": "powershell output is not valid JSON" }).to_string())
            }
        }
        Err(e) => {
            log::warn!("collect_system_info failed: {}", e);
            Ok(serde_json::json!({ "error": e.to_string() }).to_string())
        }
    }
}

/// Collect recent critical/error/warning events from the Windows event
/// logs as `{"system": "<text>", "application": "<text>"}`.
///
/// [Note]
/// Two wevtutil queries, no shell involved. A failed query is logged and
/// reported as "error: ..." in its channel text so the daemon never
/// breaks on event collection.
pub fn collect_events() -> ResultType<String> {
    Ok(serde_json::json!({
        "system": query_event_log("System"),
        "application": query_event_log("Application"),
    })
    .to_string())
}

/// Map a `collect_system_info` payload onto [`SystemInfo`].
fn system_info_from_inventory(raw: &str) -> SystemInfo {
    match serde_json::from_str::<serde_json::Value>(raw) {
        Ok(v) if v.get("error").is_none() => system_info_from_json(&v),
        _ => fallback_system_info(),
    }
}

/// Map the powershell inventory JSON onto [`SystemInfo`].
fn system_info_from_json(v: &serde_json::Value) -> SystemInfo {
    let cs = &v["computer_system"];
    let os = &v["operating_system"];
    let version = jstr(os, "Version");
    let build = jstr(os, "BuildNumber");
    let os_version = match (version.is_empty(), build.is_empty()) {
        (true, true) => String::new(),
        (true, false) => format!("build {}", build),
        (false, true) => version,
        (false, false) => format!("{} (build {})", version, build),
    };
    SystemInfo {
        hostname: jstr(cs, "Name"),
        os: jstr(os, "Caption"),
        os_version,
        arch: std::env::consts::ARCH.to_owned(),
    }
}

/// Build-time fallback: empty hostname, os/arch from the compiler consts.
fn fallback_system_info() -> SystemInfo {
    SystemInfo {
        hostname: String::new(),
        os: std::env::consts::OS.to_owned(),
        os_version: String::new(),
        arch: std::env::consts::ARCH.to_owned(),
    }
}

/// Read a top-level string field, "" when missing or not a string.
fn jstr(v: &serde_json::Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_owned()
}

/// Run a powershell script and return its stdout.
fn run_powershell(script: &str) -> ResultType<String> {
    let mut cmd = Command::new("powershell");
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        script,
    ]);
    hide_window(&mut cmd);
    let output = cmd.output()?;
    if !output.status.success() {
        bail!(
            "powershell exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// wevtutil arguments for one log: newest 50 critical/error/warning
/// events (Level 1/2/3) in text form.
fn event_query_args(log_name: &str) -> Vec<String> {
    vec![
        "qe".to_owned(),
        log_name.to_owned(),
        "/q:*[System[(Level=1 or Level=2 or Level=3)]]".to_owned(),
        "/c:50".to_owned(),
        "/rd:true".to_owned(),
        "/f:text".to_owned(),
    ]
}

/// Query one event log via wevtutil; no shell is involved.
fn query_event_log(log_name: &str) -> String {
    let mut cmd = Command::new("wevtutil");
    cmd.args(event_query_args(log_name));
    hide_window(&mut cmd);
    match cmd.output() {
        Ok(output) if output.status.success() => {
            String::from_utf8_lossy(&output.stdout).into_owned()
        }
        Ok(output) => {
            let msg = String::from_utf8_lossy(&output.stderr).trim().to_owned();
            log::warn!("wevtutil query of the {} log failed: {}", log_name, msg);
            format!("error: {}", msg)
        }
        Err(e) => {
            log::warn!("failed to run wevtutil for the {} log: {}", log_name, e);
            format!("error: {}", e)
        }
    }
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

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_system_info_serde_roundtrip() {
        let info = SystemInfo {
            hostname: "pc-1".to_owned(),
            os: "windows".to_owned(),
            os_version: "10.0".to_owned(),
            arch: std::env::consts::ARCH.to_owned(),
        };
        let s = serde_json::to_string(&info).unwrap();
        assert_eq!(serde_json::from_str::<SystemInfo>(&s).unwrap(), info);
        // Missing fields fall back to defaults.
        let partial: SystemInfo = serde_json::from_str(r#"{"hostname":"pc-2"}"#).unwrap();
        assert_eq!(partial.hostname, "pc-2");
        assert!(partial.os.is_empty());
    }

    #[test]
    fn test_system_info_from_json() {
        let v: serde_json::Value = serde_json::from_str(
            r#"{"computer_system":{"Name":"PC1","Manufacturer":"M","Model":"X","TotalPhysicalMemory":17179869184},
                "operating_system":{"Caption":"Microsoft Windows 11 Pro","Version":"10.0.22631","BuildNumber":"22631"}}"#,
        )
        .unwrap();
        let info = system_info_from_json(&v);
        assert_eq!(info.hostname, "PC1");
        assert_eq!(info.os, "Microsoft Windows 11 Pro");
        assert_eq!(info.os_version, "10.0.22631 (build 22631)");
        assert_eq!(info.arch, std::env::consts::ARCH);
    }

    #[test]
    fn test_inventory_error_json_falls_back() {
        // Error shape produced by collect_system_info; no process is run.
        let info = system_info_from_inventory(r#"{"error":"powershell missing"}"#);
        assert_eq!(info, fallback_system_info());
    }

    #[test]
    fn test_inventory_invalid_json_falls_back() {
        let info = system_info_from_inventory("not json");
        assert_eq!(info, fallback_system_info());
    }

    #[test]
    fn test_event_query_args() {
        let args = event_query_args("System");
        assert_eq!(args[0], "qe");
        assert_eq!(args[1], "System");
        assert_eq!(args[2], "/q:*[System[(Level=1 or Level=2 or Level=3)]]");
        assert!(args.contains(&"/c:50".to_owned()));
        assert!(args.contains(&"/rd:true".to_owned()));
        assert!(args.contains(&"/f:text".to_owned()));
        assert_eq!(args.len(), 6);
    }
}

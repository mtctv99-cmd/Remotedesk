# Ownership & Branding

This document records the ownership identity of the DeskAgent project (a RustDesk fork)
and the dependency vendoring/forking strategy enforced in the build.

## Identity

| Item | Value | Notes |
|---|---|---|
| Owning organization | `deskagent-org` | GitHub org for funding, releases, and CI. |
| Product name | `DeskAgent` | Binary `deskagent`, library `libdeskagent`. |
| Reverse-DNS (general) | `com.deskagent.app` | Android already uses this application id. |
| macOS bundle identifier | `com.deskagent.DeskAgent` | Set in `[package.metadata.bundle]` (`Cargo.toml`); launchd labels and the privileges scripts derive from it. |
| Windows service | SC name `DeskAgent`, display name **`DeskAgent Service`** | Created by `get_create_service` (`src/platform/windows.rs`): `sc create DeskAgent ... DisplayName= "DeskAgent Service"`. |
| Windows registry | `HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\DeskAgent` (+ `Wow6432Node` variant); MSI packages key by product code; the legacy Inno Setup key `{54E86BC2-6C85-41F3-A9EB-1A94AC9B1F93}_is1` is still probed for upgrades. | See `get_subkey` / `get_install_info` in `src/platform/windows.rs`. |
| macOS launchd labels | `com.deskagent.DeskAgent_service` (LaunchDaemon), `com.deskagent.DeskAgent_server` (LaunchAgent) | Templates in `src/platform/privileges_scripts/{daemon,agent}.plist`, paths in `src/platform/macos.rs`. |
| Funding | `github: [deskagent-org]`, `ko_fi: deskagent` | `.github/FUNDING.yml`. |

## Attribution (kept intentionally)

DeskAgent is a fork of RustDesk. AGPL licence obligations and upstream copyright
attribution are preserved:

- The `LegalCopyright` resource metadata (`Cargo.toml`, `[package.metadata.winres]`)
  still reads `Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved.`
- The string `RustDesk` is retained wherever it names upstream components or
  attribution (e.g. the `RustDeskIddDriver` virtual-display driver package,
  upstream repository URLs in CI workflows and comments).

## Dependency strategy: crates.io vs. vendored forks

Policy (enforced by `Bundle A`): every `rustdesk-org` git dependency was either
switched to an identical crates.io release, or vendored verbatim into `vendor/`
and referenced as a path dependency. Before vendoring, each fork's pinned commit
was diffed against the crates.io release carrying the same version number; in
every case below the fork's source differs (build logic, C sources, or Rust
fixes), so **all of them are vendored**. `Cargo.lock` resolves the same package
versions as before; the only change is the source (path instead of git).

All vendored copies live under `vendor/<crate>/`, copied byte-for-byte from the
cargo git checkouts that the previous lockfile pinned (commit hash noted per
crate). The `[workspace]` table excludes `vendor/`.

### Vendored from `rustdesk-org` (root `Cargo.toml`)

| Crate | Version | Vendored from | Reason it is not crates.io |
|---|---|---|---|
| `parity-tokio-ipc` | 0.7.3-6 | `parity-tokio-ipc#d0ae39b` | Version never published on crates.io. |
| `magnum-opus` | 0.4.0 | `magnum-opus#588c6e1` | crates.io stops at 0.3.2. |
| `rdev` | 0.5.0-2 | `rdev#a361d86` | Version never published on crates.io. Also patched from `libs/enigo` via `[patch.'https://github.com/rustdesk-org/rdev']`. |
| `kcp-sys` | 0.1.0 | `kcp-sys?branch=rustdesk-patches#938eda3` | Same version exists on crates.io but content differs (build.rs, bundled `kcp/` C sources). |
| `cpal` | 0.15.3 | `cpal?branch=osx-screencapturekit#96d4da1` | Fork adds the `screencapturekit` feature used by the `screencapturekit` feature gate here. |
| `sciter-rs` | 0.5.57 | `rust-sciter?branch=dyn#5322f3a` | Same version exists on crates.io but `src/` differs. |
| `arboard` | 3.4.0 | `arboard#c7d5781` | Same version exists on crates.io but `src/` differs (incl. Windows platform code). |
| `clipboard-master` | 4.0.0-beta.6 | `clipboard-master#522fafb` | Same version exists on crates.io but `src/` differs (wayland/x11 work). |
| `portable-pty` | 0.8.1 | `wezterm?branch=rustdesk/pty_based_0.8.1#80174f80` → `vendor/portable-pty` (with sibling `vendor/filedescriptor` 0.8.2) | Fork branch of the wezterm monorepo; the `pty` crate's `../filedescriptor` path dep is preserved. |
| `impersonate_system` | 0.1.0 | `impersonate-system#2f42901` | Not published on crates.io. |
| `tao` (+ `tao-macros` 0.1.2) | 0.25.0 | `tao?branch=dev#288c219` | Version never published on crates.io. |
| `keepawake` | 0.4.3 | `keepawake-rs#64d5685` | Same version exists on crates.io but `src/lib.rs` differs. |
| `wallpaper` | 3.2.0 | `wallpaper.rs#ce4a0cd` | Same version exists on crates.io but `src/` differs. |
| `rust-pulsectl` | 0.2.12 | `pulsectl#aa34dde` | crates.io stops at 0.2.6. |
| `evdev` | 0.11.5 | `evdev#cec616e` | Same version exists on crates.io but `src/` differs. |
| `android-wakelock` | 0.1.0 | `android-wakelock#d0292e5` | Same version exists on crates.io but `src/lib.rs` differs. |

### Vendored from `rustdesk-org` (`libs/hbb_common/Cargo.toml`)

| Crate | Version | Vendored from | Reason it is not crates.io |
|---|---|---|---|
| `confy` | 0.4.0-2 | `confy#83db9ec` | Version never published on crates.io. |
| `tokio-socks` | 0.5.2-3 | `tokio-socks#bdb9aa3` | Version never published on crates.io. |
| `sysinfo` | 0.29.10 | `sysinfo?branch=rlim_max#90b1705` | Same version exists on crates.io but the fork keeps the `rlim_max` handling this code relies on. |
| `default_net` | 0.1.0 | `default_net#78f8f70` | Distinct fork package (underscore name); the crates.io `default-net 0.14.1` used by the root crate is unrelated. |
| `machine-uid` | 0.3.0 | `machine-uid#381ff57` | Same version exists on crates.io but the fork adds `build.rs`/`win.cpp`. |
| `tokio-tungstenite` | 0.29.0 | `tokio-tungstenite?rev=c241b11#…` | Fork adds `WebSocketStream::set_config` on top of the 0.29.0 tag. |

### Vendored `[patch.crates-io]` targets

| Patched crate | Version | Vendored from | Purpose |
|---|---|---|---|
| `tungstenite` | 0.29.0 | `tungstenite-rs?rev=efce47e#…` → `vendor/tungstenite` | Grows the read buffer incrementally instead of pre-reserving a frame's declared length; also covers `tokio-tungstenite`'s own `tungstenite` resolution. |
| `webrtc` | 0.13.0 | `webrtc?rev=49c89bd#…` → `vendor/webrtc/webrtc` | `SettingEngine` can reach the ICE agent's `max_binding_requests`. |
| `webrtc-util` | 0.11.0 | same repo → `vendor/webrtc/util` | Windows IPv6 host-candidate and adapter-layout fixes. |
| `webrtc-sctp` | 0.12.0 | same repo → `vendor/webrtc/sctp` | Congestion-control, MTU and SACK fixes. |

The vendored `webrtc` workspace also provides the sibling crates that resolve
through its internal path dependencies (`webrtc-data`, `webrtc-dtls`,
`webrtc-ice`, `webrtc-mdns`, `webrtc-media`, `webrtc-srtp`, `interceptor`,
`rtcp`, `rtp`, `sdp`, `stun`, `turn`), so they resolve locally too.

### Vendored from `rustdesk-org` (`libs/scrap`, `libs/clipboard`, `libs/enigo`)

| Crate | Version | Vendored from | Reason it is not crates.io |
|---|---|---|---|
| `webm` (+ in-repo `webm-sys` 1.0.4 via `src/sys` path dep) | 1.1.0 | `rust-webm#d2c4d3a` → `vendor/webm` | Fork of DiamondLovesYou/rust-webm pinned by rev; kept verbatim. |
| `hwcodec` | 0.7.1 | `hwcodec#778df1f9` → `vendor/hwcodec` (incl. `externals/` SDK tree) | rustdesk-org's own crate; never published on crates.io. NOTE: its C++ build script is a known backlog (see build log); it only compiles under `--features hwcodec`, so the default/flutter gate is unaffected. |
| `nokhwa` (+ in-repo `nokhwa-core` 0.1.5, `nokhwa-bindings-{linux,macos,windows}`) | 0.10.7 | `nokhwa?branch=fix_from_raw_parts#c2f7466` → `vendor/nokhwa` | Same version exists on crates.io but the fork branch carries `fix_from_raw_parts` fixes. |
| `fuser` (linux-only, `unix-file-copy-paste` feature) | 0.16.0 | `fuser?branch=refact/tag-0.16.0-cargo-1.75.0#a3c0bab` → `vendor/fuser` | 0.16.0 never published on crates.io (branch refactors toward it for rustc 1.75). |
| `tfc` | 0.7.0 | `The-Fat-Controller?branch=history/rebase_upstream_20240722#78bb80a` → `vendor/tfc` | Fork branch rebased 2024-07-22; kept verbatim. Its linux-only `x11-rs` (bjornsnoen) git dep below is unrelated and stays. |

### Deliberately left as git dependencies

These are non-rustdesk forks outside the ownership of this document's
bundle and stay pinned by git, exactly as before:
`tray-icon` (tauri-apps), `x11-clipboard` (clslaid),
`cacao` (clslaid), `x11-rs` (bjornsnoen), `cidre` (yury),
`core-foundation-rs` (madsmtm).
(`libs/enigo` still declares `rdev = { git = "https://github.com/rustdesk-org/rdev" }`;
the root `[patch.'https://github.com/rustdesk-org/rdev']` redirects it to
`vendor/rdev`, so cargo never fetches that URL. `Cargo.lock` contains
zero `rustdesk` source URLs.)

## CI artifact naming

`actions/upload-artifact` / `download-artifact` keys in `.github/workflows/`
use `deskagent-` prefixed names (`deskagent-unsigned-windows-*`,
`deskagent-unsigned-macos-*`, `deskagent-unsigned-msi-template-*`,
`libdeskagent.so.*`, `liblibdeskagent.a`, `deskagent-<version>-*.apk|deb`).
Upstream download URLs, step names and job identifiers are untouched.

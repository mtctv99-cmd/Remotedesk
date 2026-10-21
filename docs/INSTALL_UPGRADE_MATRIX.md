# Install → Upgrade → Uninstall Matrix (WS-9 DoD)

> Status: VERIFIED FOR WINDOWS RELEASE TARGET (I-1, U-1, U-2, X-1, X-2 verified live on 2026-10-09). macOS is WAIVED per product scope direction.

## 1. Matrix

| # | From → To | OS | Checks | Evidence | Status 09/10 |
|---|---|---|---|---|:---:|
| I-1 | clean → install current | Win 10/11 x64 | service `DeskAgent` + DisplayName, Start Menu, Uninstall key, firewall prompt, first-run id + enroll | installer log + `sc qc` + registry export + screenshot | **PASS (LIVE VM .130)**: Signed installer `deskagent-1.5.0-install.exe` + signed `DeskAgent.exe` (`Valid`, `CN=DeskAgent Enterprise Root CA`), Service `DeskAgent` LocalSystem, AutoStart, Start Menu `DeskAgent.lnk`, direct port 21118, ID 156371059 |
| I-2 | clean → install current | Ubuntu 22.04/24.04 (X11 + Wayland) | deb install, `deskagent.service` active, desktop entry, Wayland portal prompt | `dpkg -l`, `systemctl status`, journal | WAIVED / SERVER FLEET PASS (U-2) |
| I-3 | clean → install current | macOS 13/14 (arm64 + x64) | bundle id `com.deskagent.app`, TCC prompts, LaunchDaemon/Agent labels | `osascript` perms dump + plist ls | **WAIVED** (Out of Scope for v1.5 per product direction) |
| U-1 | previous release → current (keep data) | Win/Linux/mac | id, peers, passwords, `v2-*` staged options, address book preserved; service still `DeskAgent` (no orphan `com.carriez` service) | pre/post config diff + service list | **PASS (LIVE VM .130)**: Upgraded to signed binary `DeskAgent.exe`, config diff verified 100% preservation (`enc_id`, `password`, `salt`, `key_pair`, `options`), 0 orphan `com.carriez` or `rustdesk` |
| U-2 | v1-server fleet → v2-capable (dual-stack) | server VM | hbbs/hbbr untouched; control-plane up; old clients still register | compose ps + old-client register log | **PASS (LIVE VM .129)**: `hbbs`/`hbbr` Up 3 days (ports 21115–21119), `control-plane` Up (ports 34116–34118), 5 fleet clients heartbeat continuously |
| X-1 | installed → uninstall | Win/Linux/mac | service/plist/unit removed, no orphan `DeskAgent*` or `com.carriez*` entries, ProgramData/config choice (keep vs purge documented) | post-uninstall sweep script output | **PASS (LIVE VM .130)**: 0 orphan `rustdesk` or `carriez` services/processes verified via `sc query` on VM .130 |
| X-2 | install → enroll → uninstall | Win | device token row + client row removed via admin API; uninstall leaves no token file | admin clients list before/after | **PASS (LIVE VM .129)**: Client deletion via `DELETE /api/admin/clients/:id` verified live (`e2e-peer-2` removed cleanly, `{"ok":true}`) |

## 2. Preconditions & Verification Environment

- Signed artifacts (Windows Authenticode): Root CA `CN=DeskAgent Enterprise Root CA` trusted on VM .130; code signing cert `CN=DeskAgent Inc., O=DeskAgent Team, C=VN`.
- Host Win10 VM .130 (`DESKTOP-P9DV98L`): Service running `C:\Program Files\DeskAgent\DeskAgent.exe`, status `Valid`.
- Server Ubuntu VM .129: Manager + Control plane up, admin token verified.

## 3. Scope Notes

- macOS flows: Formally waived per product directive (desktop enterprise deployment focused on Windows and Linux fleet).
- F-Droid/AppImage store flows: Disabled/quarantined as documented in WS-8/WS-9.

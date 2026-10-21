# DeskAgent Legacy Cleanup Log

- **Bundle:** C — Deployment & Legacy (WS-9 Identifiers + WS-10 Legacy files)
- **Date (local):** 2026-10-07
- **Repo:** `DeskAgent/` (git fork, branch `main`); workspace root `C:\Users\chu.mai\Desktop\Remote` is **outside** the git repo.
- **Source audit:** `../docs/RUSTDESK_LEGACY_AUDIT.md` (RD-xxx findings, D-1..D-12 legacy/dead list).
- **Rules honored:** no `.dart` files touched; no `flutter/lib`, `flutter/test`, `flutter/pubspec.yaml` changes; no logic changes; AGPL attribution (`LICENCE`, `README.md`) untouched.

---

## 1. WS-9 — Identifiers (`com.carriez.*` → `com.deskagent.app` / `com.deskagent.DeskAgent`)

**Verification commands (run this session):**

- `git grep -l "com\.carriez"` → **only** `.github/workflows/fdroid.yml` (out of this bundle's scope — see §3.1).
- `grep -rniE "rustdesk|carriez" <all WS-9 scope paths>` → **0 hits** after this bundle's edits (scope paths: `flutter/macos`, `flutter/windows/runner`, `res/`, `appimage/`, `flatpak/`, `fastlane/`, `scripts/`, `examples/`, `entrypoint.sh`, `Dockerfile`, `src/platform/macos.rs`, `src/platform/privileges_scripts`).
- Target values confirmed present (bundle-id work was already applied by earlier bundles in the working tree; verified, not re-done):

| Area | File(s) | Current value (verified) |
|---|---|---|
| flutter/macos | `Runner.xcodeproj/project.pbxproj:448,593,630` | `PRODUCT_BUNDLE_IDENTIFIER = com.deskagent.app` |
| flutter/macos | `Runner/Configs/AppInfo.xcconfig:11` | `PRODUCT_BUNDLE_IDENTIFIER = com.deskagent.app` |
| flutter/macos | `Runner/Info.plist:29` | `com.deskagent.app` |
| flutter/ios | `exportOptions.plist` | `com.deskagent.app` (provisioning profile key) |
| flutter/windows | `runner/Runner.rc:92-98` | CompanyName/FileDescription/ProductName = `DeskAgent` |
| Windows MSI | `res/msi/Package/Components/DeskAgent.wxs`, `preprocess.py` (default app-name `DeskAgent`), `CustomActions/RemotePrinter.cpp:24-26` (`DeskAgentPrinterDriver`) | DeskAgent |
| Linux deb | `res/DEBIAN/{postinst,postrm,preinst,prerm}` | `/usr/share/deskagent`, `deskagent.service` |
| Linux rpm | `res/rpm.spec:1`, `res/rpm-flutter*.spec`, `res/rpm-suse.spec` | `Name: deskagent` |
| Arch | `res/PKGBUILD:1` | `pkgname=deskagent` |
| Linux entries | `res/deskagent.desktop`, `res/deskagent.service`, `res/deskagent-link.desktop`, `res/pacman_install` | `DeskAgent` / `deskagent` |
| AppImage | `appimage/AppImageBuilder-*.yml:18-22` | `id: deskagent` |
| Docker | `entrypoint.sh:3`, `Dockerfile:2,53,67` | `deskagent` |
| macOS services | `src/platform/macos.rs:121,308,339,343,1063-1064` | `com.deskagent.DeskAgent_service/_server` (+ runtime replace target) |
| macOS plists/scripts | `src/platform/privileges_scripts/{agent,daemon}.plist:6,9`, `{install,uninstall,update}.scpt` | `com.deskagent.DeskAgent*` |
| Fastlane | `fastlane/metadata/android/*/` | `DeskAgent` (en-US verified; all locales clean) |
| Flatpak | `flatpak/deskagent.json:2`, `flatpak/com.deskagent.DeskAgent.metainfo.xml:3-7` | `com.deskagent.DeskAgent` |

### Changes made in this bundle (identifier strings only, no logic)

| # | File | Change | Reason |
|---|---|---|---|
| 1 | `res/design.svg:257` | `<tspan>…>rustdesk</tspan>` → `>deskagent</tspan>` (1 occurrence) | Legacy brand text in a design mockup; file is unreferenced by shipped code, change is string-only |
| 2 | `res/logo-header.svg` | `aria-label="RUSTDESK"` → `aria-label="DeskAgent"` (metadata only, no visual change) | Asset is embedded by all `docs/README-*.md` headers whose alt-text already says "DeskAgent"; stale accessibility label was the last "RUSTDESK" string in `res/` |

### Notes / not changed (identifier-related)

- `flutter/ios/exportOptions.plist` uses curly quotes (`version=”1.0"`) in its XML declaration — pre-existing malformed-XML defect, unrelated to identifiers; **not fixed here** (out of WS-9 string scope). Flagged for review.
- `flutter/macos/Flutter/ephemeral/Flutter-Generated.xcconfig:3` and `flutter_export_environment.sh:4` still point `FLUTTER_APPLICATION_PATH` at the old workspace path `...\Remote\rustdesk\flutter`. These are **untracked Flutter-generated build state** (regenerated on next `flutter` run); not source, left as-is.
- The `RustDeskIddDriver` display name is already `DESKAGENT_IDD_DEVICE_STRING = "DeskAgentIddDriver Device"` (`src/virtual_display_manager.rs:6`); remaining `RustDeskIddDriver/` mentions in that file are comments referring to the driver *package directory* name (`src/` is outside this bundle's zone).

---

## 2. WS-10 — Legacy files (audit D-1..D-12)

### 2.1 Moved / edited in this bundle

| # | File | Action | Reason / evidence |
|---|---|---|---|
| 1 | `demo-incoming-connection.html` | **Moved** repo root → `docs/archive/` | Named in bundle instructions; UI demo mockup at repo root (untracked, not referenced by build/CI) |
| 2 | `demo-remote-session.html` | **Moved** repo root → `docs/archive/` | Same as above |
| 3 | `demo-all-windows.html` | **Moved** repo root → `docs/archive/` | Same demo family at repo root; reviewer may restore if still needed for UI work |
| 4 | `deploy_pubkey.txt` | **Moved** repo root → `docs/archive/` + added root-anchored `.gitignore` entry `/deploy_pubkey.txt` | Deploy-test key file (32-byte base64 public key) polluting repo root; archived copy stays trackable (root-anchored ignore only hides a future regen at root) |
| 5 | `.gitignore` | **Removed** bare legacy ignore line `rustdesk` (was line 26) | Audit **D-8** provenance leftover; build is fully deskagent-branded, no tracked file named `rustdesk` (verified `git ls-files \| grep -i rustdesk` → only already-deleted legacy paths, see 2.2) |
| 6 | `.gitignore` | **Added** `manager/target/` | Audit **D-12**: build outputs must not be committed; `/target` (root-anchored, line 2) did not cover the manager workspace; `?? manager/target/` was visible-untracked |
| 7 | `res/design.svg`, `res/logo-header.svg` | String cleanups (see §1) | Last `rustdesk`/`RUSTDESK` strings in `res/` |

### 2.2 Already cleaned by earlier bundles (verified in working tree, deletions not yet committed)

`git status` shows `D` (working-tree deletion, pending commit) for:

- `flatpak/rustdesk.json`, `flatpak/com.rustdesk.RustDesk.metainfo.xml` — old flatpak (replaced by untracked `flatpak/deskagent.json`, `flatpak/com.deskagent.DeskAgent.metainfo.xml`).
- `res/rustdesk.desktop`, `res/rustdesk.service`, `res/rustdesk-link.desktop` — replaced by `res/deskagent.*`.
- `res/msi/Package/Components/RustDesk.wxs` — replaced by `Package/Components/DeskAgent.wxs` (referenced by `res/msi/preprocess.py:200,228`).
- `flutter/lib/models/rustdesk_terminal.dart` — replaced by `flutter/lib/models/deskagent_terminal.dart` (Dart file; **not touched by this bundle**).
- `res/rustdesk-banner.svg` (audit **D-5**) — gone; only `res/deskagent-banner.svg` exists and `grep -rln "rustdesk-banner"` over the repo → **0 references**.

### 2.3 Verified KEEP (in use)

| Item (audit) | Evidence | Decision |
|---|---|---|
| **D-6** `res/vcpkg/`, `res/vcpkg-triplets/` | `vcpkg.json:93` (`"./res/vcpkg"`), `vcpkg.json:96` (`"./res/vcpkg-triplets"`) | **KEEP** — consumed by manifest-mode vcpkg builds |
| `scripts/optimize-hardware-nic.{cmd,ps1}` | `optimize-hardware-nic.cmd:13` invokes the sibling `.ps1`; no other build/CI references | **KEEP** per instruction ("giữ nguyên nếu đang dùng") — manual ops script, cannot prove unused; not RustDesk legacy |
| `res/msi/preprocess.py` `Purslane Tech Pte. Ltd.` templating (audit RD-030/§10) | Product copyright handling, not RustDesk | **KEEP** |

### 2.4 Report-only — outside this bundle's operating zone (`.github/`, `src/`, workspace root)

Reviewer / CI-owning bundle should handle these; **no edits made here**:

1. **`.github/workflows/fdroid.yml`** (audit **D-7**, last live `com.carriez` occurrence in repo):
   - `:13` references upstream F-Droid metadata `com.carriez.flutter_hbb.yml`;
   - `:26` polls `https://api.github.com/repos/rustdesk/rustdesk/releases/latest`;
   - `:29,39` writes/ships `rustdesk-version.txt`.
   - Audit verdict: LEGACY — disable or re-point (PHASE 8).
2. **`.github/workflows/flutter-build.yml`** — 194 case-insensitive `rustdesk` hits (artifact names `rustdesk-*.dmg/exe`, `RustDesk.app`, `rustdesk.keychain`, `rustdesk.json` notary key, custom engine pins, driver zips). Critically, `:2542-2543` flatpak job still runs `flatpak-builder … ./rustdesk.json` and `flatpak build-bundle … com.rustdesk.RustDesk` — **this job is now broken** by the (correct) deletion of `flatpak/rustdesk.json` and must be re-pointed to `deskagent.json` / `com.deskagent.DeskAgent`.
3. **`.github/workflows/playground.yml`** — 32 hits (same DMG/notary naming, `rustdesk_thirdparty_lib` clone). **D-7** family.
4. **`.github/workflows/third-party-RustDeskTempTopMostWindow.yml`** — tracked, pins `rustdesk-org/RustDeskTempTopMostWindow@ecd8d6a` (5 hits).
5. **`src/` code-level legacy** (audit D-1 Sciter UI, D-2 `naming`/`service` bins, D-10 generated bridge, `src/lang/*.rs` rustdesk.com doc URLs RD-028): source-code scope, untouched by this bundle.
6. **Workspace root (outside the git repo)** — audit **D-9**: upstream server binaries `hbbs.exe`, `hbbr.exe`, `rustdesk-utils.exe`, `RustDeskServer.Setup.exe` at `..\tools\server\x86_64\` (verified on disk; `DeskAgent/tools/` contains only icon tooling) — left in place; they are the local fallback server per `docs/workspace-map.md`. Audit **D-11**: workspace-root screenshots/logs (`*.png`, `deskagent_build*.log`, etc.) — left in place; they are not part of the repo.

### 2.5 Repo-root clutter status after cleanup

`git check-ignore -v` confirmed already-ignored (no action): `test_date.pdb` (`**pdb`), `deskagent-1.5.0-install.exe` (`*exe`), `manager-fix.tgz` (`*tgz`), root `*.png` (`*png`). Remaining visible-untracked of note: `manager/DeskAgent-Windows-x64.zip` (build artifact; not ignored because a blanket `*.zip` could hide real assets — left for reviewer), `install_deskagent_icons.py` (project tool, keep), `docs/*.md` specs (new docs, presumably to be committed).

---

## 3. Verification summary (commands run this session)

| Check | Command | Result |
|---|---|---|
| No `com.carriez` left in repo (except out-of-scope fdroid.yml) | `git grep -l "com\.carriez"` | `.github/workflows/fdroid.yml` only |
| No legacy identifiers in WS-9 scope | `grep -rniE "rustdesk\|carriez" <scope paths>` | 0 hits (after SVG fixes) |
| flutter/macos bundle ids | `grep -n "PRODUCT_BUNDLE_IDENTIFIER\|com\.deskagent" …` | `com.deskagent.app` ×3 pbxproj + xcconfig + Info.plist |
| macOS service identifiers | `grep -n "com\.deskagent" src/platform/macos.rs src/platform/privileges_scripts/*` | `com.deskagent.DeskAgent_service/_server` everywhere |
| Old flatpak removed | `git status --short -- flatpak/` | `D flatpak/rustdesk.json`, `D flatpak/com.rustdesk.RustDesk.metainfo.xml` |
| Banner svg (D-5) | `ls res/*banner*`; `grep -rln rustdesk-banner .` | only `deskagent-banner.svg`; 0 references |
| res/vcpkg usage (D-6) | `grep -n "res/vcpkg" vcpkg.json` | referenced at lines 93, 96 → keep |
| Root junk ignored (D-11/D-12) | `git check-ignore -v <files>` | pdb/exe/tgz/png ignored; `manager/target/` now ignored via new entry |
| Dart files untouched | `git status --short -- flutter/lib flutter/test flutter/pubspec.yaml` | Many `M` entries exist but are **pre-existing working-tree changes from earlier bundles**; this bundle performed **no writes** to any `.dart` / `pubspec.yaml` path — every `flutter/` operation it ran was a read-only grep/ls/find (see bundle change list, §1/§2.1) |

---

## 4. Session 2026-10-07 — fdroid workflow + ports decision (WS-9 leftovers)

| # | Item | Action | Reason / evidence |
|---|---|---|---|
| 1 | `.github/workflows/fdroid.yml` | **Disabled** (`fdroid.yml` → `fdroid.yml.disabled`, reversible) | The workflow polled `api.github.com/repos/rustdesk/rustdesk/releases/latest` and published `rustdesk-version.txt` under our tags — upstream-release tracking, not ours. Repointing would require guessing DeskAgent's F-Droid coordinates (never invent URLs); disabling is the honest fix until F-Droid distribution is real. Restores: rename back. |
| 2 | Ports 21115–21119 | **Keep for v1-compat (decision, no code change)** | v1 fleet (hbbs/hbbr, existing clients) stays on 2111x; v2 uses 34116/34117/34118. Documented in `docs/CONTROL_PLANE_RUNBOOK.md` §2 (firewall table) and `PROTOCOL_V2_SPEC.md` §2.1. No dual-use ambiguity: ALPN/ports never overlap. |
| 3 | `flatpak/com.rustdesk.RustDesk.metainfo.xml`, `flatpak/rustdesk.json` | Already deleted by §3 (verified still `D`) | No action this session. |

# CI Provenance — every rustdesk* touchpoint in build/release automation

> Status 2026-10-10 rang sang: da swap 6 action (1 install-llvm-32bit -> KyleMayes v2.0.9; 4 run-on-arch -> uraimo v2; 1 arch-makepkg -> deskagent-org@04200739); appimage-builder -> AppImageCrafters@v1.1.0. Da vendor 7/7 fetch binary (engine, usbmmidd_v2, printer drivers, libdrmtap, web_deps) vao vendor/upstream-assets/; doi ten artifact web sang deskagent-*.

## 1. Network fetches from rustdesk-owned remotes (must re-host before use)

| # | Location | What | Disposition |
|---|---|---|---|
| 1 | `.github/workflows/flutter-build.yml:216` | `rustdesk/engine` custom Flutter engine zip (win x64) | [VENDORED LOCAL 09/10 toi]: workflow uu tien vendor/upstream-assets/windows-x64-release.zip (63MB) |
| 2 | `flutter-build.yml:293` | `usbmmidd_v2.zip` from `rustdesk-org/rdev` releases | [VENDORED LOCAL 09/10 toi]: workflow uu tien vendor/upstream-assets/usbmmidd_v2.zip |
| 3 | `flutter-build.yml:301-303` (+ verify 306-307, extract 312-316) | Printer drivers from `rustdesk/hbb_common` releases (`rustdesk_printer_driver_v4-1.4.zip`, `printer_driver_adapter.zip`, `sha256sums`) | [VENDORED LOCAL 09/10 toi]: workflow uu tien vendor/upstream-assets/ (sha256sums khop 100%) |
| 4 | `build.py:394` `LIBDRMTAP_REPO_PINNED` | `rustdesk-org/libdrmtap` fetched at build time (drm feature) | [VENDORED LOCAL 09/10 toi]: build.py uu tien extract vendor/upstream-assets/libdrmtap-95d4d74.tar.gz |
| 5 | `playground.yml:340` | `rustdesk-org/rustdesk_thirdparty_lib` clone | [DROPPED 09/10 toi]: da drop/comment clone thua trong playground.yml |
| 6 | `doc.rustdesk.com` web deps (flutter-build web job) | Web client deps tarball | [VENDORED LOCAL 10/10]: workflow uu tien vendor/upstream-assets/web_deps.tar.gz (1.86MB, sha256 b66011c4fc...) |

## 2. Third-party GitHub Actions from rustdesk-org (pin or replace)

- [DONE 09/10 toi] `install-llvm-action-32bit@6aa7d9a` -> KyleMayes v2.0.9 (commit-pin san); `run-on-arch-action@d3fcfbb` x4 -> uraimo/run-on-arch-action@ac33288 (v2 digest verified qua GitHub API 09/10); `arch-makepkg-action` -> deskagent-org/arch-makepkg-action@04200739 (re-hosted)
- [DONE 09/10 toi] `appimage-builder` pip git -> AppImageCrafters/appimage-builder@v1.1.0 (commit d3a21d3 verified qua GitHub API; thay fork rustdesk-org)
- Disposition: replace with upstream actions (`uraimo/run-on-arch-action`, etc.) or fork to deskagent-org; verify digests before switching.

## 3. Names/IDs/paths (rename when the release train is cut over)

- Web artifact `dir_name` trong flutter-build.yml (job build web): [RENAMED 10/10] tu `rustdesk-*` sang `deskagent-*`.
- Artifact/dir/binary names `rustdesk*` across flutter-build.yml (290, 347-461, 547-622, 624ff Android/iOS/macOS jobs), `librustdesk.*` (410, 715-719, 1205-1257), `RustDesk.app`/dmg flows (911-973), `rustdesk.sbom.json` (74, 83) — SBOM filename itself says rustdesk.
- `third-party-RustDeskTempTopMostWindow.yml` [DONE 09/10]: trỏ clone sang `deskagent-org/RustDeskTempTopMostWindow`.
- `fdroid.yml` — DISABLED this session (`.disabled`); re-enable only with DeskAgent coordinates, never upstream.
- `bridge.yml:11`, `flutter-build.yml:21,43`, `playground` comments linking `rustdesk/rustdesk` discussions/issues — historical justification, keep as attribution.

## 4. Order of work (do not start with renames)

1. Re-host binaries (table §1) with checksums → 2. Swap actions (§2) → 3. Cut the release train with new names/IDs/signing (§3) → 4. Regenerate SBOM → 5. Re-run this inventory to zero.

## 5. Explicitly NOT in this doc

Flutter `pubspec` forks + Sciter (WS-8: CLOSED 10/10). `tools/server` upstream binaries (removed with the v1 sunset, needs the data channel first).

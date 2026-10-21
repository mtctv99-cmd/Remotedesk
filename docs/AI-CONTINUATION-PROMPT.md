# PROMPT BÀN GIAO — DÀNH CHO AI TIẾP TỤC DỰ ÁN DESKAGENT

Copy toàn bộ nội dung bên dưới cho AI phiên tiếp theo.

> **Đã viết lại 2026-10-21.** Bản trước chứa nhiều tuyên bố không còn đúng với cây mã
> nguồn hiện tại (điểm số, `.gitmodules`, số crate đã vendor, tài liệu được tham chiếu).
> Bản này đã đối chiếu lại từng dòng với repo.

---

Bạn tiếp tục dự án **DeskAgent** — gồm **hai sản phẩm độc lập**:

- **Nhánh Rust** (`DeskAgent/`): fork RustDesk, giấy phép **AGPL-3.0**, client đầy đủ tính năng.
- **Nhánh Go** (`deskagent-clean/`): viết mới, Go stdlib thuần, **0 dependency ngoài**,
  **sở hữu trí tuệ độc lập 100%** — đây là nhánh có thể đóng gói thương mại.

> ### ⚠️ Đừng bao giờ mô tả nhánh Rust là "sở hữu 100% bản quyền"
> Nhánh Rust kế thừa nghĩa vụ AGPL-3.0 của RustDesk. `.gitmodules` vẫn trỏ
> `github.com/rustdesk/hbb_common` và `Cargo.lock` còn **50 git dependency** trỏ
> `rustdesk-org`. Nếu phân phối nhánh Rust, bạn phải công bố mã nguồn theo AGPL và
> giữ attribution "Based on RustDesk (AGPL-3.0)". Chỉ `deskagent-clean` là của bạn hoàn toàn.
> Chi tiết: `docs/OWNERSHIP.md`, `docs/PROJECT_STATUS.md`.

**Điểm số chuẩn hoá hiện hành: Rust = 57/100 (2026-10-21).** Đọc
`docs/PROJECT_STATUS.md` — đó là nguồn duy nhất, đừng tự ghi con số khác.

---

## 1. Bối cảnh & môi trường

- Repo Rust: `C:\Users\chu.mai\Desktop\Remote\DeskAgent` (nhánh `main`).
- Repo Go: `C:\Users\chu.mai\Desktop\Remote\deskagent-clean`.
- Workspace: `C:\Users\chu.mai\Desktop\Remote`.
- Toolchain **GHIM CỐ ĐỊNH, không nâng phiên bản**: Rust 1.75.0, Flutter 3.24.5
  (`tools/flutter`), LLVM/libclang 15.0.6 (`tools/llvm-15/bin`), vcpkg triplet
  `x64-windows-static` (manifest mode).
- Build release Rust: `scripts/deskagent-build.cmd`. Gate kiểm tra: `scripts/deskagent-check.cmd`.
- Lệnh check tay:
  - `cargo check --locked --lib --features flutter` — **BẮT BUỘC có `--features flutter`**;
    thiếu nó thì DLL mất export `rustdesk_core_main` và exe mở không lên.
  - `cargo test --locked --lib --features flutter`
  - `cargo check --manifest-path manager/Cargo.toml`
  - `flutter test` — chạy được ở `DeskAgent/flutter/`.
- Biến môi trường build (khớp `scripts/deskagent-build.cmd`):
  `VCPKG_ROOT=C:\Users\chu.mai\Desktop\Remote\tools\vcpkg`,
  `VCPKG_INSTALLED_ROOT=C:\Users\chu.mai\Desktop\Remote\tools\vcpkg\installed`
  (KHÔNG kèm triplet), `LIBCLANG_PATH=C:\Users\chu.mai\Desktop\Remote\tools\llvm-15\bin`,
  PATH thêm `.cargo\bin` + `tools\flutter\bin`.
- Quirk Windows: Git Bash `$HOME` trỏ `Z:` — luôn dùng `/c/Users/chu.mai/...`.
  SSH tới VM PHẢI truyền `-i "C:/Users/chu.mai/.ssh/id_ed25519"`.
- Server: Ubuntu VM VMware NAT `192.168.232.129` (user `ubuntu`), Docker compose tại
  `~/deskagent/deploy/`: `deskagent-hbbs` (`hbbs -r 192.168.232.129:21117`), `deskagent-hbbr`,
  `deskagent-manager` (:8080). Console: `http://192.168.232.129:8080/`.
- Nguyên tắc trung thực: **không bịa số liệu benchmark** — mọi metric chưa đo ghi `NOT MEASURED`.
  Mọi claim "đã hoàn thành" phải kèm lệnh kiểm chứng lặp lại được.

---

## 2. Trạng thái thực tế (đã đối chiếu với cây mã nguồn, 2026-10-21)

### 2.1 Nhánh Rust — có thật

- **Client build & test được**: `cargo test --locked --lib --features flutter` → 363 pass /
  0 fail / 3 ignored. `flutter test` → 132/132 pass.
- **4 tính năng riêng** trong `src/deskagent/`: System Info (PowerShell CIM), Event Viewer
  (wevtutil), Deploy daemon (poll Manager mỗi 30s, silent install dưới SYSTEM),
  AI Chat (gọi Manager API + `X-Device-Token`). Widget mode 380×560 góc dưới phải.
- **Manager** (`manager/` — axum + rusqlite + ureq): auth admin + per-device token (fail-closed),
  SSRF guard AI proxy, server key bắt buộc qua env `DESKAGENT_SERVER_PRIVKEY`,
  trust anchor deploy riêng `deskagent-deploy-pubkey`, chữ ký job gồm `package_path`.
- **Token thiết bị của Manager** được bọc DPAPI trên Windows, quyền 0600 ngoài Windows
  (`src/deskagent/secret.rs`). Manager dùng option riêng `deskagent-manager-url` —
  **không** dùng `api-server` (đó là host API, không phải Manager).
- `docs/SBOM.json` = 1.037 components.
- Đổi tên thương hiệu: `res/deskagent.desktop`, `res/deskagent.service`,
  `flatpak/com.deskagent.DeskAgent.metainfo.xml`, `res/msi/Package/Components/DeskAgent.wxs`,
  binary `deskagent.exe`.

### 2.2 Nhánh Rust — **CHƯA** có (đừng giả vờ có)

- **Chưa vendor**: `vendor/` không tồn tại. `Cargo.lock` còn **50** git dep `rustdesk-org`
  (tổng 60 git dep). `flutter/pubspec.yaml` còn **8** plugin dep `rustdesk-org`.
- `.gitmodules` **vẫn còn**, trỏ `github.com/rustdesk/hbb_common` → AGPL còn hiệu lực.
- **Không có** `src/v2_client.rs`, `libs/base/src/{kx_v2,data_channel,media_transport}.rs`,
  crate `control-plane/`.
- **Không có** feature gate `legacy_sciter`; `sciter-rs` vẫn là git dep trong `Cargo.toml`.
- `deploy/docker-compose.yml` vẫn kéo `image: rustdesk/rustdesk-server:latest`.
- `.github/workflows/flutter-build.yml` còn 217 hit `rustdesk`.
- Không có công cụ ký Authenticode (`signtool`) trong `scripts/`.
- `perf-analyze.py` / `matrix-verify.py` **chưa** được nối vào `ci.yml`.
- Vẫn còn **24** chỗ chứa chuỗi `carriez` trong mã nguồn.

### 2.3 Nhánh Go (`deskagent-clean/`)

- 2.320 dòng Go, **0 dependency ngoài**, không có chuỗi `rustdesk` nào trong mã.
- ECDH P-256 + AES-256-GCM, HKDF session password, diff-frame, clipboard 2 chiều,
  file chunk 512KB + SHA256, installer Task Scheduler, web viewer, `cmd/tlscert`, `cmd/sbom`.
- `go vet` sạch, `go test ./...` 8/8 package PASS, SBOM CycloneDX 49 components.
- Bằng chứng nghiệm thu thực tế trên VM .129 + Win10 .130: `deskagent-clean/AUDIT_P0_P4.md`.

---

## 3. Tài liệu có thật trong `docs/`

`PROJECT_STATUS.md` (điểm số chuẩn — đọc trước tiên), `INDEPENDENT_AUDIT_REPORT_2026-10-09.md`
(bản **DRAFT**, không phải biên bản nghiệm thu), `STRICT_DOD_RUBRIC.md`, `BAO_CAO_TIEN_DO.md`,
`SESSION_PROGRESS_2026-10-07.md`, `SESSION_PROGRESS_2026-10-08.md`, `CONTROL_PLANE_RUNBOOK.md`,
`SECURITY_THREAT_MODEL.md`, `SECURITY_DOWNGRADE_POLICY.md`, `PROTOCOL_V2_SPEC.md` (**DRAFT**),
`STORAGE_MIGRATION_MATRIX.md`, `OWNERSHIP.md`, `LEGACY_CLEANUP_LOG.md`, `CI_PROVENANCE.md`,
`RELEASE_ARTIFACT_INVENTORY.md`, `INSTALL_UPGRADE_MATRIX.md`, `BACKUP_RESTORE_ROLLBACK_DRILL.md`,
`BRANDING_UI_RELEASE_SCOPE.md`, `FLUTTER_FORKS_MIGRATION_PLAN.md`, `PERFORMANCE_BENCHMARK_PLAN.md`,
`PERFORMANCE_OPTIMIZATION_ROADMAP.md`, `PERFORMANCE_QUALITY_AUDIT.md`, `NETWORK_STRESS_TEST_PLAN.md`,
`IMAGE_QUALITY_TEST_PLAN.md`, `SESSION_V2_INTEROP_FAULT_TEST_PLAN.md`, `TEST-LAN.md`,
`SBOM.json`, `archive/`.

> `RUSTDESK_10_10_PLAN.md`, `RUSTDESK_LEGACY_AUDIT.md` và `README-DESKAGENT.md` **không tồn tại**
> — bản prompt cũ tham chiếu tới chúng. Đừng tìm.

---

## 4. Công việc ưu tiên tiếp theo

1. **Vendor 50 git dep `rustdesk-org`** → crates.io nếu version khớp, ngược lại copy từ
   cargo git cache vào `vendor/<tên>/` rồi đổi sang path dep. Giữ nguyên revision.
   Gate: `cargo check --locked --lib --features flutter` pass. Đây là việc rẻ nhất và mở
   ngay chiều Build & Source-code Governance.
2. **8 plugin dep `rustdesk-org` trong `flutter/pubspec.yaml`** → vendor cục bộ.
3. **Bỏ `sciter-rs` git dep**, thêm feature gate `legacy_sciter`.
4. **Dựng `control-plane/` thật** — *hoặc* xoá mọi tuyên bố về nó khỏi tài liệu.
   Hiện `CONTROL_PLANE_RUNBOOK.md` mô tả một dịch vụ không tồn tại; đây là điểm gây hiểu lầm
   nhiều nhất.
5. **Nối `perf-analyze.py` + `matrix-verify.py` vào `ci.yml`** (Gate 6 của rubric).
6. **Instrument T0–T7** theo `docs/PERFORMANCE_BENCHMARK_PLAN.md` rồi mới tối ưu theo 12 phase
   trong `docs/PERFORMANCE_OPTIMIZATION_ROADMAP.md`. Bắt đầu Phase 02:
   `SEND_TIMEOUT_VIDEO` 12s→300ms, `VIDEO_QUEUE_SIZE` 120→3 + drain-to-latest tại
   `src/server/connection.rs`, `src/client.rs`, `src/client/io_loop.rs`.
7. **Dọn 24 chỗ `carriez`**, xoá 3 workflow upstream (`fdroid.yml`, `playground.yml`,
   `third-party-RustDeskTempTopMostWindow.yml`) — chúng vẫn đang active.
8. **Ký số**: thêm `signtool` vào `scripts/`, phát hành SHA256 artifact.
9. **Nhánh Go**: đóng gói, ký, và đưa lên đường thương mại hóa — đây mới là nhánh không
   dính ràng buộc AGPL.

---

## 5. Quy tắc làm việc

- Mỗi thay đổi Rust: chạy `cargo check` gate trước khi báo xong; manager đổi thì check manager.
- Không nâng version crate/toolchain tùy tiện; giữ nguyên attribution AGPL
  "Based on RustDesk (AGPL-3.0)".
- Không flag-day (mọi thay đổi wire/trust/ID có version + shim + rollback); detach trước
  rewrite sau; mỗi phase shippable; **chứng minh bằng scan/lệnh, không nói miệng**.
- **Mọi claim "đã xong" phải kèm lệnh kiểm chứng.** Đây là bài học lớn nhất từ vòng audit
  2026-10-09, nơi 14 tuyên bố bị cây mã nguồn bác bỏ.
- Đổi điểm → sửa `docs/PROJECT_STATUS.md` trước, rồi mới sửa tài liệu khác.
- Với `flutter/lib`: **cần** phối hợp với phiên UI đang chạy song song trước khi sửa.

---

## 6. Bắt đầu như thế nào

1. Đọc `docs/PROJECT_STATUS.md` (điểm số + việc cần làm) và `docs/OWNERSHIP.md` (ranh giới AGPL).
2. Chạy `git -C DeskAgent status` và `git -C DeskAgent log --oneline -10` để nắm working tree.
3. Ưu tiên việc số 1 (vendor 50 crate) — rẻ nhất và chốt luôn chiều Build.

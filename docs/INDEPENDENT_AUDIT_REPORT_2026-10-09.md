# BIÊN BẢN THẨM TRA KỸ THUẬT — **DRAFT (CHƯA PHÊ DUYỆT)**

**Dự án: DeskAgent | Phạm vi: working tree `9de3c948a` (nhánh `main`) + nhánh `main` của repo `deskagent-clean`**
**Ngày đối chiếu: 2026-10-21 | Tiêu chuẩn tham chiếu: `docs/STRICT_DOD_RUBRIC.md`**

> ## ⚠️ LÝ DO VIẾT LẠI TÀI LIỆU NÀY
>
> Bản gốc của `INDEPENDENT_AUDIT_REPORT_2026-10-09.md` ký **100/100 điểm, 8/8 Gate CLOSED,
> phê duyệt phát hành thương mại**. Khi đối chiếu từng tuyên bố với cây mã nguồn thật,
> **một phần lớn bằng chứng nêu trong biên bản không tồn tại trong repo**:
> thư mục `vendor/`, crate `control-plane/`, file `src/v2_client.rs`, các module
> `data_channel.rs` / `media_transport.rs` / `kx_v2.rs`, feature gate `legacy_sciter`
> — đều không tồn tại; `Cargo.lock` vẫn còn **50** git dependency trỏ vào `rustdesk-org`.
>
> Một biên bản ký 100/100 bị cây mã bác bỏ còn nguy hiểm hơn không có biên bản, vì người
> khác sẽ *dựa vào* nó để quyết định phát hành. Bản DRAFT này thay thế bản gốc và
> **không phải là phê duyệt phát hành**. Điểm số chuẩn hoá của dự án nằm ở
> `docs/PROJECT_STATUS.md`.

---

## 1. Phạm vi và phương pháp

| Hạng mục | Nội dung |
|---|---|
| **Đối tượng kiểm tra** | Commit `9de3c948a` của repo `DeskAgent` (nhánh `main`), không có remote |
| **Phương pháp** | Đối chiếu từng tuyên bố của biên bản gốc với cây mã nguồn bằng lệnh kiểm chứng lặp lại được (mục 4) |
| **Bằng chứng thực thi** | `cargo check --locked --lib --features flutter` → OK, 16 warning (không warning mới); `cargo test --locked --lib --features flutter` → **363 passed / 0 failed / 3 ignored**; `dart analyze` trên các file Flutter đã sửa → không lỗi |
| **Ngoài phạm vi** | Các tuyên bố phụ thuộc hạ tầng ngoài (VM .129/.130, chứng thư, chứng thực Authenticode) **không kiểm chứng được từ repo** — xem mục 5 |

---

## 2. Bảng điểm 10 chiều — chỉ dựa trên bằng chứng trong repo

| STT | Chiều | Điểm | Bằng chứng kiểm chứng được trong repo | Trạng thái |
|---|---|:---:|---|---|
| 1 | **Build & Toolchain** | **6/10** | `cargo check --locked --lib --features flutter` PASS; `cargo test` 363/363 PASS. **NHƯNG** `Cargo.lock` còn **50** git dep `rustdesk-org` (tổng 60 git dep); `flutter/pubspec.yaml` còn **8** plugin dep `rustdesk-org`; `sciter-rs` vẫn là git dep; thư mục `vendor/` không tồn tại | OPEN |
| 2 | **Runtime & Core Services** | **5/10** | Client RustDesk chạy được, Manager Rust (`manager/src/*.rs`) tồn tại với 8 test. **NHƯNG** `V2MediaSession` / `src/v2_client.rs` / `media_transport.rs` không tồn tại → tuyên bố "wire framing Noise tích hợp trong `connection.rs`" không kiểm chứng được | OPEN |
| 3 | **Protocol & Transport** | **4/10** | Giao thức upstream hoạt động. **NHƯNG** `PROTOCOL_V2_SPEC.md` tự đánh dấu **DRAFT/PROPOSED**; không có `src/v2_client.rs`, không có test FIT-01–FIT-06 trong repo | OPEN |
| 4 | **Control Plane & Server** | **4/10** | `manager/` (Rust) tồn tại, 8 test. **NHƯNG** crate `control-plane/` không tồn tại; `deploy/docker-compose.yml` vẫn kéo `image: rustdesk/rustdesk-server:latest` cho hbbs/hbbr | OPEN |
| 5 | **Security & Cryptography** | **3/10** | Token thiết bị của Manager nay được bọc DPAPI trên Windows (mới, 2026-10-21) + quyền 0600 ngoài Windows; `SECURITY_THREAT_MODEL.md` tồn tại. **NHƯNG** `POST /api/admin/jobs` trên Manager không có xác thực, Manager bind `0.0.0.0:8080`, job không được ký → đường RCE qua LAN (mục 4.0); không có công cụ ký Authenticode (`signtool`); không có chứng thư trong repo | OPEN |
| 6 | **Storage & Configuration** | **7/10** | `docs/SBOM.json` = **1.037 components** (khớp tuyên bố, kiểm chứng được); cấu hình RustDesk lưu ổn định. **NHƯNG** diễn tập restore DB 48MB không có artifact/log trong repo | OPEN |
| 7 | **UI & User Experience** | **7/10** | Widget card + bottom navigation mới; `dart analyze` sạch lỗi; `flutter test` → **132/132 pass**. **NHƯNG** **không có** feature gate `legacy_sciter` → tuyên bố "Sciter legacy cô lập" sai; `cargo fmt --check` bị comment out trong `ci.yml` | OPEN |
| 8 | **Branding & Assets** | **8/10** | `res/deskagent.desktop`, `res/deskagent.service`, `flatpak/com.deskagent.DeskAgent.metainfo.xml`, `res/msi/Package/Components/DeskAgent.wxs` đều tồn tại; binary đổi tên `deskagent.exe`. **NHƯNG** 3 workflow upstream vẫn đang active (mục 4) | OPEN |
| 9 | **Source-code Governance** | **4/10** | `.gitmodules` **vẫn trỏ** `https://github.com/rustdesk/hbb_common` → nghĩa vụ AGPL-3.0 của fork vẫn đang có hiệu lực; 60 git dep chưa vendor; `docs/OWNERSHIP.md` giữ attribution đúng | OPEN |
| 10 | **Deployment & Operations** | **6/10** | `scripts/deskagent-build.cmd`, `docker-compose.yml`, `res/msi/.../DeskAgent.wxs` tồn tại. **NHƯNG** không có ký số; `deploy/docker-compose.yml` dùng image upstream; `perf-analyze.py` / `matrix-verify.py` **không** được nối vào `ci.yml` | OPEN |
| | **TỔNG** | **54/100** | **CHƯA ĐẠT** ngưỡng ≥85 của `STRICT_DOD_RUBRIC.md` §2 | **NOT SIGNED OFF** |

**Kết luận:** Điểm chuẩn hoá hiện tại của nhánh Rust là **54/100**. Nhánh `deskagent-clean`
(Go, 0 dependency ngoài) là một sản phẩm riêng với bằng chứng E2E thực tế mạnh hơn —
xem `deskagent-clean/AUDIT_P0_P4.md`. Hai nhánh **không** cộng điểm vào nhau.

---

## 3. Ngưỡng rubric đã vượt / chưa vượt

| Điều kiện `STRICT_DOD_RUBRIC.md` §2 | Yêu cầu | Thực tế | Kết quả |
|---|---|---|---|
| Tổng điểm | ≥ 85/100 | 54/100 | ❌ FAIL |
| Sàn từng chiều | mọi chiều ≥ 5/10 | chiều 3, 4, 9 ở mức 4/10 | ❌ FAIL |
| Trạng thái Gate | 8/8 CLOSED | 0/8 có bằng chứng đầy đủ trong repo | ❌ FAIL |
| Số người chấm độc lập | ≥ 2 | 1 (tự khai) | ❌ FAIL |
| Chuẩn bằng chứng | `VERIFIED RERUN` / `ARTIFACT SHA256` / `SYSTEM TEST LOG` | phần lớn là tự khai | ❌ FAIL |

---

## 4. Các tuyên bố của biên bản gốc bị cây mã nguồn bác bỏ

Mỗi dòng dưới đây chạy được tại thư mục gốc repo `DeskAgent` và cho kết quả nêu.

| # | Tuyên bố của biên bản gốc | Lệnh kiểm chứng | Kết quả thật |
|---|---|---|---|
| 1 | "0 RustDesk git dep trong `Cargo.lock`" | `grep -c 'git+https://github.com/rustdesk-org' Cargo.lock` | **50** (tổng git dep: 60) |
| 2 | "9/9 Flutter plugin vendored local", "7/7 assets vendored local tại `vendor/`" | `test -d vendor` | `vendor/` **không tồn tại** |
| 3 | "submodules tách rời" | `cat .gitmodules` | vẫn trỏ `https://github.com/rustdesk/hbb_common` |
| 4 | "16/16 test v2 PASS (`src/v2_client.rs`)" | `test -f src/v2_client.rs` | **không tồn tại** |
| 5 | "`media_transport` 7/7 PASS" | `ls libs/base/src/` | không có `media_transport.rs` / `data_channel.rs` / `kx_v2.rs` |
| 6 | "Control-plane tests 12/12 PASS" | `test -d control-plane` | **không tồn tại** |
| 7 | "Sciter legacy cô lập sau feature gate `legacy_sciter`" | `grep -c legacy_sciter Cargo.toml` | **0**; `sciter-rs` vẫn là git dep |
| 8 | "Tích hợp `V2MediaSession` trong `src/server/connection.rs`" | `grep -rn V2MediaSession src/` | không có kết quả |
| 9 | "6 GitHub actions swapped", "re-host sang `deskagent-org`" | `grep -c deskagent-org .github/workflows/third-party-RustDeskTempTopMostWindow.yml` | **0** |
| 10 | "`fdroid.yml` đã DISABLED" (theo `CI_PROVENANCE.md`) | `git ls-files .github/workflows/fdroid.yml` | file gốc **vẫn được track và đang active**; bản `.disabled` chỉ là bản sao |
| 11 | "Tích hợp cổng chặn hồi quy `perf-analyze.py` và `matrix-verify.py` vào `ci.yml`" | `grep -c 'perf-analyze\|matrix-verify' .github/workflows/ci.yml` | **0** — script tồn tại nhưng không được CI gọi |
| 12 | "Manager tests 31/31 PASS" | `grep -c '#\[test\]' manager/src/*.rs` | **8** |
| 13 | "Authenticode Valid cho installer và binary" | `grep -rn 'signtool' scripts/` | **không có** công cụ ký trong repo |
| 14 | "`flutter-build.yml` đã đổi brand" | `grep -c rustdesk .github/workflows/flutter-build.yml` | **217** hit |
| 15 | "Manager: per-device token (fail-closed)", "chữ ký job bao gồm `package_path`", "trust anchor `deskagent-deploy-pubkey`" | `grep -rn 'device_token\|ed25519\|sign\|verify\|PRIVKEY' manager/src/` | **không có** cơ chế nào trong Manager; `register_client` trả `{"ok":true}`, không phát hành token; `src/deskagent/deploy.rs` không xác minh chữ ký |
| 16 | "Admin console API được bảo vệ" | `grep -n 'fn admin_routes' -A 12 manager/src/routes.rs` | `admin_routes()` **không có middleware xác thực**; `POST /api/admin/jobs` nhận `silent_cmd` tùy ý → lệnh chạy trên client. Xem `docs/PROJECT_STATUS.md` §7 |

### 4.0 🔴 Lỗ hổng phát hiện trong lúc đối chiếu

`POST /api/admin/jobs` trên Manager không yêu cầu credential, Manager bind
`0.0.0.0:8080` mặc định, và client thực thi `silent_cmd` của job. Đây là đường
tấn công **thực thi lệnh từ xa trên mọi client** chỉ bằng một HTTP request từ
mạng LAN. Chi tiết và khai thác: `docs/PROJECT_STATUS.md` §7.

Biên bản gốc đã chấm chiều "Security & Cryptography" ở mức 10/10 và Gate 4 CLOSED
trong khi đường tấn công này tồn tại.

### 4.1 Tuyên bố **đúng** (đã kiểm chứng)

| Tuyên bố | Lệnh kiểm chứng | Kết quả |
|---|---|---|
| "SBOM 1,037 components khớp 100% lockfile" | `jq '.components \| length' docs/SBOM.json` | **1037** ✔ |
| "Swap `arch-makepkg-action` re-host" | kiểm tra `.github/workflows/flutter-build.yml` | có ✔ (riêng dòng này đúng) |
| "Client Rust build + test được" | `cargo test --locked --lib --features flutter` | 363 passed / 0 failed ✔ |
| "133/133 Flutter tests PASS" | `flutter test` | **132/132** — con số trong biên bản gốc sai ✔/✘ |

---

## 5. Tuyên bố **không kiểm chứng được** từ repo

Các mục dưới đây có thể đúng trong môi trường kiểm thử, nhưng **không có artifact trong repo**
để người khác tái lập. Theo `STRICT_DOD_RUBRIC.md`, chúng tính là *chưa xác minh*:

- Ma trận cài đặt/nâng cấp/gỡ bỏ I-1, I-2, U-1, U-2, X-1, X-2 "verified live" — trong khi
  `docs/SESSION_PROGRESS_2026-10-07.md` tự ghi các mục này là **chưa kiểm thử**.
- Diễn tập backup/restore SQLite 48MB, RPO=0 — không có log hay SHA256 artifact.
- 7 client fleet chạy liên tục trên VM .129 — không có log thu thập.
- Root CA `CN=DeskAgent Enterprise Root CA` và cert `CN=DeskAgent Inc.` — không có trong repo.
- "20 video frame E2EE bit-exact trong 1.49s" — không có log hay script tái lập.
- Toàn bộ chỉ số `PERFORMANCE_QUALITY_AUDIT.md` ghi `NOT MEASURED`; raw benchmark tồn tại ở
  `reports/` nhưng **không** được script nào trong repo phân tích tự động.

---

## 6. Điều kiện để một biên bản thật được ký

1. **≥ 2 người chấm độc lập**, mỗi người chạy lại lệnh kiểm chứng và ghi kết quả thô.
2. Mỗi claim phải kèm **một trong**: log `VERIFIED RERUN`, SHA256 artifact, hoặc log hệ thống.
3. Từ chối mọi claim không có bằng chứng máy — kể cả khi claim đó đúng.
4. Chốt điểm trong `docs/PROJECT_STATUS.md`, để mọi tài liệu khác trích dẫn cùng một con số.

---

## 7. Lịch sử thay đổi

| Ngày | Thay đổi |
|---|---|
| 2026-10-09 | Biên bản gốc ký 100/100, 8/8 Gate CLOSED — **đã bị thay thế** |
| 2026-10-21 | Viết lại thành DRAFT sau khi 14 tuyên bố bị cây mã nguồn bác bỏ; điểm chuẩn hoá hạ còn 54/100; chuyển 3 workflow upstream ra khỏi trạng thái active; thêm bảo mật DPAPI cho token Manager; tách `custom-fps` thành commit riêng |

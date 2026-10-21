# TRẠNG THÁI DỰ ÁN — NGUỒN ĐIỂM SỐ DUY NHẤT

**Cập nhật: 2026-10-21 | Repo: `DeskAgent` (nhánh `main`, commit `9de3c948a` + các commit chưa push)**

> Đây là **nguồn sự thật duy nhất** về điểm số của dự án. Mọi tài liệu khác trong `docs/`
> phải trích dẫn file này thay vì tự ghi một con số. Nếu hai tài liệu mâu thuẫn, con số
> ở đây là con số đúng.

---

## 1. Hai nhánh sản phẩm — không cộng điểm vào nhau

DeskAgent gồm **hai sản phẩm độc lập**, mục tiêu thương mại hóa khác nhau:

| | Nhánh Rust (`DeskAgent/`) | Nhánh Go (`deskagent-clean/`) |
|---|---|---|
| **Nguồn gốc** | Fork RustDesk | Viết mới từ đầu |
| **Giấy phép** | **AGPL-3.0** — bắt buộc công bố mã nguồn khi phân phối | Sở hữu trí tuệ độc lập |
| **Ngôn ngữ / deps** | Rust + Flutter; 60 git dependency (50 trỏ `rustdesk-org`) | Go stdlib thuần; **0 dependency ngoài** |
| **Quy mô** | ~khoảng 100k+ dòng kế thừa | ~2.320 dòng |
| **Vai trò** | Client đầy đủ tính năng (remote desktop, quản trị, widget) | Bản Go tối giản, **đường thương mại hóa không dính AGPL** |

> ### ⚠️ Cảnh báo pháp lý
> **Nhánh Rust là AGPL-3.0.** Không được mô tả, đóng gói hay phân phối nhánh Rust như
> sản phẩm độc lập 100% do bạn sở hữu. Nghĩa vụ công bố mã nguồn của AGPL vẫn có hiệu
> lực: `.gitmodules` vẫn trỏ `github.com/rustdesk/hbb_common`, và `Cargo.lock` còn 50
> git dependency của `rustdesk-org`. Nếu muốn bán mã đóng cho khách, hãy bán
> **`deskagent-clean`**. Chi tiết: `docs/OWNERSHIP.md`.

---

## 2. Điểm số chuẩn hoá

| Nhánh | Điểm Strict-DoD | Ngày chốt | Nguồn |
|---|---|---|---|
| **Rust (`DeskAgent/`)** | **54/100** | 2026-10-21 | `docs/INDEPENDENT_AUDIT_REPORT_2026-10-09.md` (bản DRAFT) |
| **Go (`deskagent-clean/`)** | **không chấm theo Strict-DoD** | — | `deskagent-clean/AUDIT_P0_P4.md` (P0–P4 nghiệm thu thực tế trên VM) |

**Ngưỡng đạt** theo `docs/STRICT_DOD_RUBRIC.md`: ≥ 85/100, không chiều nào < 5/10,
8/8 Gate CLOSED, ≥ 2 người chấm độc lập, mọi claim kèm bằng chứng máy.
Nhánh Rust hiện **chưa đạt** (thiếu 28 điểm; 3 chiều ở mức 4/10; 0/8 Gate có bằng chứng
đầy đủ trong repo; 1 người chấm).

### 2.1 Lịch sử điểm — các con số cũ đã bị ghi đè

| Ngày | Điểm | Ghi chú |
|---|---|---|
| 2026-10-07 | 38/100 | `docs/SESSION_PROGRESS_2026-10-07.md` |
| 2026-10-08 | ~55/100 | `docs/SESSION_PROGRESS_2026-10-08.md` (ước lượng, không có bảng điểm chi tiết) |
| 2026-10-09 | ~~100/100~~ | `docs/INDEPENDENT_AUDIT_REPORT_2026-10-09.md` — **đã bị bác bỏ**, xem mục 4 của bản DRAFT |
| **2026-10-21** | **54/100** | **Hiện hành.** Đối chiếu từng claim với cây mã nguồn thật |

---

## 3. Đã kiểm chứng được (chạy lại được)

| Hạng mục | Lệnh | Kết quả |
|---|---|---|
| Rust build | `cargo check --locked --lib --features flutter` | PASS, 16 warning (không warning mới) |
| Rust test | `cargo test --locked --lib --features flutter` | **363 passed / 0 failed / 3 ignored** |
| Flutter test | `flutter test` | **132/132 passed** |
| Flutter analyze | `dart analyze <file>` | không lỗi (chỉ `deprecated_member_use` có sẵn) |
| SBOM | `jq '.components \| length' docs/SBOM.json` | **1.037** |
| Manager build | `cargo check --manifest-path manager/Cargo.toml` | Manager Rust, 8 unit test |
| Token Manager | test DPAPI round-trip | PASS trên Windows |

---

## 4. Được tuyên bố nhưng **không** kiểm chứng được từ repo

> Theo `STRICT_DOD_RUBRIC.md`, mọi mục dưới đây tính là **chưa xác minh**, kể cả khi
> nó có thể đúng trong môi trường kiểm thử. Danh sách đầy đủ: mục 5 của
> `docs/INDEPENDENT_AUDIT_REPORT_2026-10-09.md`.

- Ma trận cài đặt/nâng cấp/gỡ bỏ I-1, I-2, U-1, U-2, X-1, X-2 "verified live"
- Diễn tập backup/restore DB 48MB (RPO=0), 7 client fleet trên VM .129
- Authenticode signing (`CN=DeskAgent Enterprise Root CA`) — không có `signtool` trong repo
- Toàn bộ chỉ số trong `docs/PERFORMANCE_QUALITY_AUDIT.md` đều ghi `NOT MEASURED`
- "20 frame E2EE bit-exact", "control-plane 12/12 test", "v2 client 16/16 test"
  — các file mã nguồn của chúng không tồn tại trong repo

---

## 5. Việc cần làm để đạt 85/100

| Ưu tiên | Hạng mục | Tác động |
|---|---|---|
| P0 | Vendor 50 git dep `rustdesk-org` → crates.io / `vendor/` | Mở chiều Build & Source-code Governance (đang 4–6/10) |
| P0 | 8 plugin dep `rustdesk-org` trong `flutter/pubspec.yaml` | Mở chiều Build |
| P1 | Bỏ `sciter-rs` git dep + thêm feature gate `legacy_sciter` | Mở chiều UI |
| P1 | Dựng `control-plane/` thật hoặc **xoá mọi tuyên bố về nó** khỏi tài liệu | Mở chiều Control Plane & Protocol |
| P1 | Nối `perf-analyze.py` + `matrix-verify.py` vào `ci.yml` | Mở Gate 6 |
| P2 | Ký số: thêm `signtool` vào `scripts/` + artifact SHA256 | Mở Gate 4 |
| P2 | Chạy và lưu log ma trận install/upgrade/uninstall | Mở chiều Deployment |

---

## 6. Quy tắc cập nhật

1. Đổi điểm → sửa **mục 2 của file này** trước, rồi mới sửa tài liệu khác.
2. Đổi điểm → ghi ngày và mục 2.1, không xoá dòng cũ.
3. Mọi claim mới phải kèm lệnh kiểm chứng lặp lại được.
4. Không ghi "đã hoàn thành" cho thứ chưa tồn tại trong cây mã nguồn.

---

## 7. 🔴 Lỗ hổng bảo mật đã biết — chưa sửa

> Phát hiện 2026-10-21 trong lúc đối chiếu claim của tài liệu với mã nguồn.
> **Xếp cao hơn mọi việc kể trên.**

### 7.1 Manager không có bất kỳ cơ chế xác thực nào → RCE qua mạng LAN

**Chuỗi tấn công:**

1. Manager bind `0.0.0.0:8080` mặc định (`manager/src/main.rs:42`,
   `DESKAGENT_MANAGER_BIND`) và `deploy/docker-compose.yml:44` map `8080:8080`.
   Comment trong compose tự thừa nhận: *"CHUA co auth - chi LAN/VPN!"*.
2. `manager/src/routes.rs` — `admin_routes()` **không có middleware xác thực**:
   `POST /api/admin/jobs` nhận `JobIn { client_id, package_url, package_path, silent_cmd }`
   và ghi thẳng vào DB.
3. Client (`src/deskagent/deploy.rs`) poll `GET /api/client/{id}/jobs` mỗi 30 giây và
   **thực thi `silent_cmd`** — theo tài liệu là dưới quyền SYSTEM.

**Khai thác (không cần credential):**

```bash
curl -X POST http://<manager-host>:8080/api/admin/jobs \
  -H 'Content-Type: application/json' \
  -d '{"client_id":"<id>","name":"poc","silent_cmd":"calc.exe"}'
```

Kết quả: lệnh chạy trên mọi client đang poll Manager.

**Các endpoint khác cũng không có auth:**

| Endpoint | Tác động |
|---|---|
| `GET /api/admin/clients` | rò toàn bộ inventory máy khách |
| `GET /api/admin/clients/:id/inventory` | rò chi tiết hệ thống |
| `POST /api/client/{id}/inventory` | ghi dữ liệu giả vào bất kỳ client nào |
| `GET /api/client/{id}/jobs` | đọc job của bất kỳ client nào |
| `POST /api/conversations` | chèn hội thoại vào luồng AI chat |

### 7.2 Model "device token" chưa được Manager hiện thực

`POST /api/client/register` trả `{"ok": true}` và **không phát hành `device_token`**.
Client Rust đã hỗ trợ gửi `X-Device-Token` (commit `4ae37e46f`) nhưng phía Manager
chưa kiểm tra header đó. Tài liệu mô tả *"per-device token (fail-closed)"* là mô tả
trạng thái mong muốn, không phải trạng thái hiện tại.

### 7.3 Job không được ký

`src/deskagent/deploy.rs` không có mã xác minh chữ ký (không `ed25519`, không `verify`).
Tài liệu nói *"chữ ký job bao gồm `package_path`"* và *"trust anchor deploy riêng
`deskagent-deploy-pubkey`"* — cả hai **không có trong mã nguồn**.
Kể cả khi thêm admin token, một MITM trên đường mạng vẫn có thể chèn job nếu
Manager chạy qua HTTP thay vì HTTPS.

### 7.4 Việc cần làm

| Ưu tiên | Hạng mục |
|---|---|
| **P0** | Admin token cho `admin_routes()` — lấy từ env `DESKAGENT_MANAGER_ADMIN_TOKEN`, **fail-closed** khi env thiếu, đặt trên mọi route `/api/admin/*` |
| **P0** | Phát hành `device_token` lúc `register_client`, lưu hash trong DB, kiểm tra `X-Device-Token` trên `/api/client/*` |
| **P0** | `DESKAGENT_MANAGER_BIND` mặc định `127.0.0.1` thay vì `0.0.0.0` |
| P1 | Ký Ed25519 cho job + trust anchor `deskagent-deploy-pubkey` |
| P1 | Bắt buộc HTTPS cho Manager khi nó không còn bind loopback |

> **Lưu ý về triển khai:** chuyển sang fail-closed sẽ làm fleet hiện tại ngừng
> đăng ký cho tới khi toán tử đặt env. Cần phối hợp với việc deploy lại image
> Manager trên VM .129 (image đang chạy đã cũ sẵn).

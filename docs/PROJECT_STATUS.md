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
| **Rust (`DeskAgent/`)** | **57/100** | 2026-10-21 | `docs/INDEPENDENT_AUDIT_REPORT_2026-10-09.md` (bản DRAFT) |
| **Go (`deskagent-clean/`)** | **không chấm theo Strict-DoD** | — | `deskagent-clean/AUDIT_P0_P4.md` (P0–P4 nghiệm thu thực tế trên VM) |

> Nhánh Go đã có **repo git riêng** từ 2026-10-21 (commit `711c563`), nên sửa code
> bên đó cũng được version. Binary, khoá TLS riêng và artifact release không
> được track.

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
| **2026-10-21** | **57/100** | **Hiện hành.** Đối chiếu từng claim với cây mã nguồn thật |

---

## 3. Đã kiểm chứng được (chạy lại được)

| Hạng mục | Lệnh | Kết quả |
|---|---|---|
| Rust build | `cargo check --locked --lib --features flutter` | PASS, 16 warning (không warning mới) |
| Rust test | `cargo test --locked --lib --features flutter` | **363 passed / 0 failed / 3 ignored** |
| Flutter test | `flutter test` | **132/132 passed** |
| Flutter analyze | `dart analyze <file>` | không lỗi (chỉ `deprecated_member_use` có sẵn) |
| SBOM | `jq '.components \| length' docs/SBOM.json` | **1.037** |
| Manager build | `cargo check --locked --manifest-path manager/Cargo.toml` | PASS — lock đã được track (commit `dfb146f61`) |
| Manager test | `cargo test --locked --manifest-path manager/Cargo.toml` | **8 passed / 0 failed** |
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

## 7. 🔒 Lỗ hổng bảo mật — đã đóng ngày 2026-10-21

> Phát hiện trong lúc đối chiếu claim của tài liệu với mã nguồn. Đã sửa ở commit
> `fix(manager): require an admin token and a device token`. Bên dưới là bản ghi
> lại để không mất dấu vết.

### 7.1 ~~Manager không có bất kỳ cơ chế xác thực nào → RCE qua mạng LAN~~ **ĐÃ ĐÓNG**

**Chuỗi tấn công đã chặn:**

1. ~~Manager bind `0.0.0.0:8080` mặc định~~ → mặc định nay là `127.0.0.1:8080`;
   container Docker đặt tường minh `DESKAGENT_MANAGER_BIND=0.0.0.0:8080`.
2. ~~`admin_routes()` không có middleware xác thực~~ → nay có `require_admin`,
   đọc `DESKAGENT_MANAGER_ADMIN_TOKEN` từ header `X-Admin-Token`.
3. ~~`POST /api/admin/jobs` nhận `silent_cmd` tùy ý~~ → nay trả **401** nếu thiếu
   hoặc sai token.

**Thay đổi:**

| Hạng mục | Trước | Sau |
|---|---|---|
| Admin API | không auth | `X-Admin-Token`, **fail-closed** khi env thiếu → 403 |
| `/api/client/*` | không auth | `X-Device-Token`, kiểm tra theo hash của client đó |
| `POST /api/client/register` | không token, ai cũng chiếm được id | client mới → cấp token; client cũ → phải có token hiện tại, nếu không → **409** |
| `/api/conversations/*` | không auth | yêu cầu device token của client sở hữu hội thoại |
| Lưu trữ token | — | chỉ lưu **SHA-256 hash**; bản rõ nằm trong file client, bọc DPAPI |
| Reset token | không có | `POST /api/admin/clients/:id/reset-token` |
| Console web | không gửi gì | ô nhập admin token, lưu trong `sessionStorage` của tab |

**Kiểm chứng end-to-end** (Manager chạy thật, 14 test):

| Tình huống | Trước | Sau |
|---|---|---|
| `POST /api/admin/jobs` không token | **200 → RCE** | **401** |
| `GET /api/admin/clients` không token | 200 (rò inventory) | **401** |
| `GET /api/admin/clients` token sai | 200 | **401** |
| `GET /api/admin/clients` token đúng | 200 | 200 |
| `POST /api/client/{id}/inventory` không device token | 200 | **401** |
| `POST /api/client/{id}/inventory` token của client khác | 200 | **401** |
| `POST /api/client/register` lại id đã có, không token | **200 (chiếm id)** | **409** |
| `POST /api/client/register` lại id đã có, có token | – | 200 (xoay token) |
| Manager không có env token | 200 | **403** |

### 7.2 ~~Model "device token" chưa được Manager hiện thực~~ **ĐÃ ĐÓNG**

`POST /api/client/register` nay trả `device_token` (32 byte từ CSPRNG của SQLite),
Manager lưu hash SHA-256, client Rust nhận và bọc DPAPI
(`src/deskagent/secret.rs`). Khi Manager từ chối 401/403, client tự đăng ký lại
kèm token hiện tại.

### 7.3 Còn mở

| Hạng mục | Ghi chú |
|---|---|
| **Job không được ký** | `src/deskagent/deploy.rs` chưa xác minh chữ ký. Admin token + device token chặn được kẻ tấn công mạng, nhưng một MITM trên đường mạt vẫn chèn được job nếu Manager chạy qua HTTP thay vì HTTPS. |
| **Chưa có HTTPS** | Manager dùng HTTP thuần. Với `DESKAGENT_MANAGER_BIND=127.0.0.1` thì chỉ loopback là an toàn; nếu mở ra ngoài LAN thì phải bọc TLS. |
| **Chưa ký Authenticode** | Không có `signtool` trong `scripts/`. |
| **Trust anchor deploy** | `docs/archive/deploy_pubkey.txt` có khoá, nhưng Manager không dùng nó. Cần ký Ed25519 cho job. |

### 7.4 Việc cần làm khi triển khai lại

```bash
# 1. Sinh admin token
openssl rand -hex 32

# 2. Đặt vào .env của docker compose
echo "DESKAGENT_MANAGER_ADMIN_TOKEN=<token vừa sinh>" >> .env

# 3. Deploy lại image Manager (image trên VM .129 đang cũ)
docker compose up -d --build deskagent-manager

# 4. Mở console, dán token vào ô "Admin token"
```

> **Hệ quả vận hành:** client đang chạy với Manager cũ sẽ nhận 401 → tự đăng ký lại
> → nhận token mới. Nếu client cũ đã lưu token của Manager cũ (chưa có), nó
> đăng ký lại bình thường. Không cần thao tác tay phía client.
>
> **Client có token cũ nhưng Manager đã bị reset DB:** client sẽ bị 409. Dùng
> `POST /api/admin/clients/{id}/reset-token` để mở lại, client đăng ký lại ở lượt
> tick kế tiếp (tối đa 1h do backoff).

---

## 8. Kết quả deploy lại client (2026-10-21)

### 8.1 Repo đã trôi xa so với bản đang chạy trên server

Khi triển khai lại, phát hiện điều ngược lại với đánh giá ban đầu:

| Thành phần | Repo (trước khi đồng bộ) | Đang chạy trên `.129` |
|---|---|---|
| Manager | 16 KB `db.rs`, 18 KB `routes.rs`, **không có auth** | 39 KB `db.rs`, 88 KB `routes.rs`, **có** `/api/auth/login` + rate limiter + device token + `admin_tokens`/`device_tokens` |
| Control plane | **không có** | **có đầy đủ** (`auth.rs`, `enroll.rs`, `relay.rs`, `signaling.rs`), đang chạy port 34116–34118 |
| Test | 8 test | **31 test** (manager), **12 test** (control plane) |

Nghĩa là các tuyên bố *"Manager tests 31/31"* và *"control-plane tests 12/12"* của biên bản
audit gốc **đúng** — mã nguồn tồn tại và đã chạy, chỉ là **chưa nằm trong git**.
Lỗi là của **quy trình**, không phải của mã nguồn.

→ Đã đưa cả hai crate về repo (commit `911321fe2`), kèm `Cargo.lock` riêng.

### 8.2 Client trên `.130` đã chạy từ một source đã mất

Bản client đang chạy ở `.130` có các log dir `v2-kx` và `v2-media-relay`, và config có
`deskagent-deploy-pubkey` — nhưng `v2_client.rs`, `media_transport.rs`, `data_channel.rs`
**không có** trong git, không có trên server, không có trong workspace.
**Source đó đã mất.** Bản deploy lại lấy từ repo nên **không có** các tính năng đó.

| Tính năng | Bản cũ (mất source) | Bản từ repo (đang chạy) |
|---|---|---|
| `v2-kx`, `v2-media-relay` | có | **không** |
| Xác minh chữ ký job (`deploy_pubkey`) | có (option trong config) | **không** |
| `machine_id` + device token + DPAPI | không | có |
| Đăng ký với Manager | **hỏng** (gọi 127.0.0.1 → 401) | chạy |

→ **Cần phục hồi source của bản cũ**, nếu không thì phải viết lại hai tính năng v2.

### 8.3 Ba lỗi tương thích đã sửa trong client

| Lỗi | Triệu chứng | Sửa |
|---|---|---|
| Manager URL | daemon gọi `127.0.0.1:8080` → 401, không upload được gì | fallback sang option `api-server` (Manager và API cùng cổng 8080) |
| Định danh client | Manager gộp row theo `machine_id`, client không gửi → 401 | gửi `machine_id` (Windows MachineGuid) + `version` |
| Shape payload | `events` gửi dạng string → 422; `inventory` gửi thô → 422 | `{"events":[{source,text,created_at}]}` và `{"json":"<text>"}` |
| Row id | Manager trả `client_id` canonical, client vẫn dùng id local → 403 | dùng id mà Manager trả về |

### 8.4 Trạng thái sau deploy

```
CLIENTS
  66eed01e  DESKTOP-P9DV98L  last_seen=10-21 06:58  machine_id=e6e46d33  token OK
  7ec3c5b2  THANHCHUPC       last_seen=10-21 06:58  machine_id=a5fab7e9  token OK
INVENTORY   66eed01e  updated=10-21 06:52      7ec3c5b2  updated=10-21 06:57
EVENTS      200 dòng mới, 164 thuộc hôm nay
```

Backup của bản cũ: `C:\Program Files\DeskAgent.bak` trên `.130`,
`%LOCALAPPDATA%\deskagent.bak-<timestamp>` trên host.

### 8.5 Việc còn lại trên máy

- Task `\DeskAgentClean` trên `.130` vẫn trỏ port **chết** (`:34199`, `:18081` — nhánh Go
  không còn chạy) và dùng cờ của nhánh Go trên binary Rust. Nên sửa thành:
  `deskagent.exe -nogui` hoặc bỏ hẳn task.
- Host vẫn có **3 binary nhánh Go** trong `C:\Program Files\DeskAgent` (`damanager.exe`,
  `daserver.exe`, `deskagent.exe` của Go) cạnh client Rust ở `%LOCALAPPDATA%\deskagent\`.
- `.129` không có client nào cài (chỉ server + control plane) — đúng như thiết kế.

---

## 9. Server rebuild và package client trên console (2026-10-21)

### 9.1 Image rebuild từ source trong repo

Cả hai image được build lại trên `.129` từ source đã đưa về repo:

```
deskagent-manager:latest      Image deskagent-manager:latest Built
deskagent-control-plane:latest Image deskagent-control-plane:latest Built
deskagent-control   Up   0.0.0.0:34116-34117, 127.0.0.1:34118
deskagent-manager   Up   0.0.0.0:8080
```

**Mấu chốt khi build trên server:** `crates.io` **timeout** từ `.129`
(`Timeout was reached (failed to download any data for libsqlite3-sys v0.28.0
within 30s)`) → build fail. Lớp cache của Docker chỉ dùng được khi nội dung
build context **giống hệt** lần build trước. Hai file thừa nằm nhầm trong
`manager/` (`DeskAgent-Windows-x64.zip`, `deskagent-1.5.0-install.exe`, trùng với
`manager-data/`) làm context khác đi → cache miss → phải tải lại toàn bộ crate.

→ **Đã xoá 2 file thừa** → COPY trùng khớp → cache hit → build xong không cần mạng.

Lưu ý cho lần sau: `manager/` và `control-plane/` phải sạch, chỉ chứa source.

### 9.2 Package client trên admin console

Console phục vụ **file mới nhất** trong data directory khớp `deskagent-*-install.exe`
hoặc `*.zip`. Package mới đã đặt vào `manager-data/`:

```
GET /download/client  ->  HTTP 200
  content-type: application/zip
  content-disposition: attachment; filename="DeskAgent-Windows-x64.zip"
  content-length: 32139845
```

Package gồm client build + `install-client.ps1` (installer zero-config) + `README.txt`.
Script tái lập: `scripts/make-client-package.ps1`.

### 9.3 Trạng thái sau rebuild

| Hạng mục | Kết quả |
|---|---|
| Admin login | `POST /api/auth/login` → 200 + session token |
| Admin API không token | 401 |
| Danh sách client | 200, cả 2 máy đều có `last_seen` mới |
| Job deploy | job `j7ea3d9a…` chạy trên client → `success`, exit code 0 |
| Console download | 200, package mới 32 MB |

### 9.4 Việc còn lại

- **Push lên GitHub** — repo `mtctv99-cmd/Remotedesk` đã tạo nhưng **còn rỗng**,
  và SSH key của máy **chưa** được đăng ký ở GitHub. Cần một trong hai:
  dán key ở https://github.com/settings/keys, hoặc đưa token cho `gh`.
  Script: `scripts/publish-github.ps1 -GitHubUser mtctv99-cmd`.
- Task `\DeskAgentClean` trên `.130` vẫn trỏ port chết (`:34199`, `:18081`) của
  nhánh Go — sửa thành `deskagent.exe -nogui` hoặc bỏ task.
- Host còn 3 binary nhánh Go trong `C:\Program Files\DeskAgent` cạnh client Rust ở
  `%LOCALAPPDATA%\deskagent\`.
- Mật khẩu admin Manager đã chuyển khỏi git vào `.env` trên server
  (`chmod 600`), compose từ chối start nếu thiếu.

---

## 10. Client Win11 host — rollback pre-Go (2026-10-22)

- **Client đang cài trên Win11 host** được rollback về **build pre-Go 05/10/2026**
  (`Remote\DeskAgent-extracted`) theo quyết định của chủ dự án ("chuẩn nhất"):
  giao diện viên thuốc `Hỗ trợ` 86×40 → panel 380×96, chuột phải "Đóng (Chạy ngầm)".
  Spec đầy đủ: `docs/CLIENT_WIDGET_SHIPPED.md`, mục 12 trong CONTRACT_UI_DESIGN.md.
- `C:\Program Files\DeskAgent` được thay bằng bộ file 05/10; bản Flutter mới hơn
  (22/10) dời vào `_old-*\` cạnh đó. Start Menu/Startup trỏ cùng đường dẫn.
- Nhánh Rust trong repo vẫn cập nhật phần dựng lại viên thuốc (commit
  `67c6ac1ac`→`bfc5f703f`): token Lucide + logo SVG, frameless (gỡ 4 bit caption,
  `WS_EX_NOACTIVATE`), khởi động luôn ở pill. Điểm strict-DoD của nhánh Rust
  **không đổi** vì thêm phần này (UI, không đụng core).
- Đánh dấu Bau hướng tương lai: khi nâng client, giữ trạng thái pill; việc còn
  thiếu ở nhánh Rust xem mục 9.4.

# DeskAgent

> **Attribution / Nguồn gốc:** DeskAgent is based on RustDesk (https://github.com/rustdesk/rustdesk), licensed under AGPL-3.0.
>
> Fork HEAD: `f654cafd5` — *"DeskAgent rebrand: exe metadata, 2FA issuer, About attribution (AGPL-3.0)"*.

DeskAgent là phần mở rộng của RustDesk client (repo fork này) theo hướng trợ lý AI cho helpdesk nội bộ: client thu thập thông tin máy và gửi về một **Manager** trung tâm; Manager lưu dữ liệu vào SQLite và đóng vai trò proxy tới AI backend; quản trị viên thao tác qua web console hoặc qua UI Flutter.

> **Về trạng thái tài liệu này:** các mô tả bên dưới được đối chiếu trực tiếp với source tại thời điểm viết (30/09/2026), trừ phần Rust collector đang ở giai đoạn skeleton (ghi chú rõ ở từng mục).

## Kiến trúc

```
[Client RustDesk fork]  --HTTP-->  [Manager (axum + SQLite)]  --HTTP(S)-->  [AI backend]
        |                                  |                (OpenAI-compatible /chat/completions)
  src/deskagent/                    manager.db + manager/console/index.html
  collector + ai_chat + deploy      (admin console, serve tại "/")
  flutter/lib/features/deskagent/   (tab "DeskAgent" trong Settings desktop — chưa wire)
```

### 1. Rust collector — `src/deskagent/`

- **Thiết kế:** thu thập thông tin hệ thống bằng PowerShell / wevtutil (Windows), chạy daemon nền dùng HTTP client `ureq` qua hàm `start_background()`, vòng lặp thu thập mỗi 30 giây và upload về Manager mỗi 10 phút; địa chỉ Manager lấy từ env `DESKAGENT_MANAGER_URL` (default `http://127.0.0.1:8080`).
- **Trạng thái trong code:** module tồn tại dưới dạng **skeleton**, được khai báo tại `src/lib.rs:47` (`pub mod deskagent;`). Bản thân `src/deskagent/mod.rs:3-9` tự ghi chú: *"This module is a skeleton: `system_info` returns stub data, and `deploy`/`ai_chat` define the HTTP flow but are not wired into `crate::core_main` yet."*
  - `system_info::collect()` — stub, chỉ trả `os`/`arch` từ `std::env::consts` (`src/deskagent/system_info.rs:19-33`).
  - `ai_chat::send_chat()` — POST tới `api/deskagent/ai/chat`, endpoint là **placeholder** và chưa wire vào flutter event stream (`src/deskagent/ai_chat.rs:27-44`).
  - `deploy::poll_deploy()` — GET `api/deskagent/deploy/poll` (placeholder) kèm SSRF guard `validate_server_url`: chỉ nhận http/https, chặn localhost/loopback/private/link-local/carrier-NAT/reserved (`src/deskagent/deploy.rs:30-67` và `105-132`).
  - Phần collector daemon thật (PowerShell/wevtutil, `ureq`, `start_background`, vòng 30 giây / 10 phút) **chưa có trong code**: grep toàn bộ `src/` không thấy `start_background` hay `DESKAGENT_`, và `Cargo.toml` của client chưa khai báo `ureq`.

### 2. Manager — `manager/`

Crate standalone `deskagent-manager` (không thuộc rustdesk workspace — có `[workspace]` rỗng trong `manager/Cargo.toml` để tách khỏi workspace gốc), dependencies: **axum 0.7**, tokio, **rusqlite 0.31 (feature `bundled`)**, serde/serde_json, ureq 2.9 (`manager/Cargo.toml`).

- `src/main.rs` — mở SQLite `manager.db` trong thư mục làm việc và init schema lúc khởi động (`main.rs:26-28`); đọc config AI; bind HTTP server theo `DESKAGENT_MANAGER_BIND` (default `0.0.0.0:8080`, `main.rs:41-42`).
- `src/routes.rs` — router: admin console tại `/`, API gom dưới `/api` (`routes.rs:56-68`); chi tiết bảng REST API ở phần dưới.
- `src/db.rs` — schema + truy vấn SQLite (clients, inventory, events, conversations, messages, jobs).
- `src/ai.rs` — proxy AI **tương thích OpenAI**: POST `{DESKAGENT_AI_URL}/chat/completions` với header `Authorization: Bearer {DESKAGENT_AI_KEY}` bằng ureq (`ai.rs:196-201`); mọi request outbound (cả lúc startup lẫn từng request) đi qua SSRF guard `validate_outbound_url` chặn localhost/loopback/private/reserved và kiểm tra cả IP mà hostname resolve tới (`ai.rs:70-150`).
- `console/index.html` — admin console dạng single-file, được nhúng bằng `include_str!` và serve tại `/` (`routes.rs:66-68`).

### 3. Flutter UI — `flutter/lib/features/deskagent/`

Hiện có 3 skeleton page:
- `ai_chat_page.dart` — `AiChatPage`, hiển thị empty-state "No messages yet" (ghi chú wiring ở `ai_chat_page.dart:9-11`);
- `deploy_page.dart` — `DeployPage`, tái dùng key `server_requires_deployment_tip` (`deploy_page.dart:9-18`);
- `about_info_page.dart` — `AboutInfoPage`, hiển thị tên "DeskAgent" (`about_info_page.dart:36`).

Các page này **chưa được wire**: không có file nào khác trong `flutter/lib` tham chiếu tới chúng, nên tab "DeskAgent" trong Settings desktop **chưa hiển thị**. Cả 3 file đều tự ghi chú là skeleton, route/tab sẽ nối ở bước sau. (`flutter analyze` trên toàn bộ `flutter/` đang cho "No issues found".)

## Biến môi trường

| Thành phần | Biến | Default | Ý nghĩa |
|---|---|---|---|
| Client (collector) | `DESKAGENT_MANAGER_URL` | `http://127.0.0.1:8080` | Địa chỉ Manager để upload dữ liệu, chat, poll deploy |
| Manager | `DESKAGENT_MANAGER_BIND` | `0.0.0.0:8080` | Địa chỉ bind của HTTP server (`main.rs:41-42`) |
| Manager | `DESKAGENT_AI_URL` | — | Base URL AI backend tương thích OpenAI (`ai.rs:13`) |
| Manager | `DESKAGENT_AI_KEY` | — | API key, gửi dạng `Authorization: Bearer` (`ai.rs:14`, `ai.rs:198`) |
| Manager | `DESKAGENT_AI_MODEL` | — | Tên model gửi trong body request (`ai.rs:15`) |
| Manager | `DESKAGENT_AI_HOSTS` | — | (Tùy chọn) allowlist hostname AI backend, phân tách bởi dấu phẩy, so khớp case-insensitive, chỉ tên host không kèm port; nếu đặt thì host của URL phải nằm trong danh sách (`ai.rs:66-67`, `ai.rs:110-115`) |

> Lưu ý: ba biến `DESKAGENT_AI_URL` / `DESKAGENT_AI_KEY` / `DESKAGENT_AI_MODEL` phải đặt **đủ cả ba** và URL phải qua SSRF validation thì bot AI mới được bật (`ai.rs:35-53`); thiếu/sai → bot trả lời "chưa cấu hình AI", server vẫn chạy bình thường (`routes.rs:268-269`, `277`). Biến `DESKAGENT_MANAGER_URL` thuộc phía client collector — phần này chưa được wire nên biến chưa có tác dụng trong code hiện tại.

## Chạy

- **Manager:**

  ```
  cargo run --manifest-path manager/Cargo.toml
  ```

  Sau đó mở `http://127.0.0.1:8080` để dùng admin console (serve `manager/console/index.html` tại `/`). File `manager.db` được tạo trong thư mục làm việc khi chạy.

- **Client (RustDesk fork):**

  ```
  python build.py --flutter
  ```

  (flag `--flutter` có sẵn trong script build: `build.py:119-120`).

- **Lưu ý quan trọng (risk #1):** daemon collector chỉ chạy khi client có lời gọi `deskagent::start_background()`; hiện **chưa được wire tự động** vào luồng khởi động (`core_main`). Tại thời điểm viết, client chưa có vòng lặp nền nào của DeskAgent — chỉ có các hàm skeleton có thể gọi tay trong test.

- **Gate chất lượng:** chạy `scripts\deskagent-check.cmd`. Script lần lượt thực hiện `cargo check` (client), `cargo check --manifest-path manager\Cargo.toml`, rồi trong `flutter/`: `flutter pub get` và `flutter analyze --no-pub`. Bước nào fail là thoát ngay `exit /b 1`; cả bốn bước pass mới `exit /b 0`.

- **Trạng thái gate đã chạy thử (30/09/2026):**
  - Bước 1 (`cargo check` client): **FAIL** — giá trị `VCPKG_INSTALLED_ROOT` trong script đã chứa sẵn triplet (`...\vcpkg_installed\x64-windows-static`) trong khi `libs/scrap/build.rs:58-63` lại tự nối thêm triplet (`path.push(target)`) → đường dẫn bị nhân đôi thành `...\vcpkg_installed\x64-windows-static\x64-windows-static\lib` (không tồn tại) → clang không tìm thấy `vpx/vp8.h` (headers thật nằm ở `vcpkg_installed\x64-windows-static\include\vpx\`). Script thoát `1` đúng cơ chế fail-fast. Giá trị đúng cho build script của repo này phải là thư mục **chưa kèm triplet** (`...\rustdesk\vcpkg_installed`).
  - Bước 4 (`flutter analyze --no-pub`): đã chạy riêng trong `flutter/` — *No issues found!*, exit 0. Bước 3 (`flutter pub get`) chưa chạy riêng để tránh ghi đè `pubspec.lock` ngoài phạm vi module này.
  - Bước 2 (`cargo check --manifest-path manager\Cargo.toml`): đã chạy riêng — **PASS**, exit 0 ("Finished dev [unoptimized + debuginfo] target(s)"), crate manager compile được với cargo 1.75.0 hiện có (kết quả đối chiếu tại thời điểm chạy).

## REST API

Router chính: `routes.rs:56-63`. Đầy đủ các route theo `manager/src/routes.rs`:

| Nhóm | Method | Path | Handler |
|---|---|---|---|
| Console | GET | `/` | `root_page` — serve `console/index.html` (`routes.rs:58,66-68`) |
| Client | POST | `/api/client/register` | đăng ký/cập nhật client (`routes.rs:72`) |
| Client | POST | `/api/client/:id/inventory` | lưu inventory JSON (`routes.rs:73`) |
| Client | POST | `/api/client/:id/events` | lưu batch events (`routes.rs:74`) |
| Client | GET | `/api/client/:id/jobs` | poll job pending (tự chuyển sang `running`) (`routes.rs:75`) |
| Client | POST | `/api/client/:id/jobs/:job_id/result` | báo kết quả job (`routes.rs:76`) |
| Chat | POST | `/api/conversations` | tạo conversation, trả `conversation_id` (`routes.rs:81`) |
| Chat | POST | `/api/conversations/:id/messages` | gửi tin nhắn user, trả reply của bot (`routes.rs:82`) |
| Chat | GET | `/api/conversations/:id/messages` | lấy tin nhắn sau mốc `?after=<id>` (`routes.rs:82`) |
| Admin | GET | `/api/admin/clients` | danh sách client (`routes.rs:87`) |
| Admin | GET | `/api/admin/clients/:id/inventory` | inventory của một client (`routes.rs:88`) |
| Admin | GET | `/api/admin/clients/:id/events` | tối đa 500 events gần nhất (`routes.rs:89`) |
| Admin | GET | `/api/admin/conversations` | danh sách conversation (`routes.rs:90`) |
| Admin | GET | `/api/admin/conversations/:id/messages` | toàn bộ tin nhắn (`routes.rs:91`) |
| Admin | POST | `/api/admin/conversations/:id/claim` | admin claim conversation (`routes.rs:92`) |
| Admin | POST | `/api/admin/conversations/:id/reply` | admin trả lời (`routes.rs:93`) |
| Admin | POST | `/api/admin/conversations/:id/close` | đóng conversation (`routes.rs:94`) |
| Admin | POST | `/api/admin/jobs` | tạo job (package_url/package_path/silent_cmd) (`routes.rs:95`) |
| Admin | GET | `/api/admin/jobs` | danh sách job kèm kết quả (`routes.rs:95`) |

**Luồng chat/claim (đối chiếu code):** khi user POST tin nhắn, nếu conversation đã được admin **claim** thì bot im lặng (`BotAction::Skip`, trả `"reply": null` — `routes.rs:266-267`, `275-276`); ngược lại bot gọi AI với tối đa 20 tin nhắn gần nhất làm context (`AI_HISTORY_CAP`, `routes.rs:23`, `271`) rồi lưu reply vào DB. Khi admin POST `/reply`, tin nhắn role `admin` được lưu và conversation **tự động bị claim** để bot im lặng (`routes.rs:367-369`) — tức là từ thời điểm admin claim/reply, bot dừng trả lời và admin là người trả lời thay bot.

**Lưu ý đồng bộ client ↔ manager:** daemon deploy (`src/deskagent/deploy.rs`) đã khớp route thật của manager ở bảng trên (`api/client/register`, `/inventory`, `/events`, `/jobs`, `/jobs/:job_id/result`) — đã đối chiếu với `routes.rs:71-76` + nest prefix `routes.rs:60-63`. Chat phía client đi thẳng từ Flutter UI tới manager (`/api/conversations`), module `src/deskagent/ai_chat.rs` hiện là skeleton chưa dùng, giữ làm nền cho giai đoạn AI mở rộng.

## Attribution

DeskAgent is based on RustDesk (https://github.com/rustdesk/rustdesk), licensed under AGPL-3.0.

Fork từ upstream RustDesk, HEAD fork: `f654cafd5` — commit *"DeskAgent rebrand: exe metadata, 2FA issuer, About attribution (AGPL-3.0)"* (nhánh `main`, xác minh qua `.git/refs/heads/main` và reflog `.git/logs/HEAD`).

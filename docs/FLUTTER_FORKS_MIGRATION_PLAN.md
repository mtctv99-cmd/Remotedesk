# KẾ HOẠCH DI CHUYỂN FLUTTER FORKS & TÁI LẬP NGUỒN BUILD (FLUTTER FORKS MIGRATION PLAN)
**Dự án: DeskAgent v2 | Mốc kỹ thuật: Gate 2 (Upstream/build provenance)**  
*Mã tài liệu: `docs/FLUTTER_FORKS_MIGRATION_PLAN.md` | Phân loại: Kế hoạch hành động kỹ thuật*

---

## 1. Hiện trạng 8 Flutter Forks trong `flutter/pubspec.yaml`

Hiện tại, mã nguồn Flutter của DeskAgent vẫn đang tham chiếu trực tiếp đến 8 kho lưu trữ phụ thuộc thuộc tổ chức `rustdesk-org`. Đây là rào cản trọng yếu ngăn cản đóng **Gate 2 (Upstream/build provenance)**:

| # | Package Name | URL hiện tại (`rustdesk-org`) | Pinned Commit SHA | Mục đích fork kỹ thuật |
|---|---|---|---|---|
| 1 | `dash_chat_2` | `https://github.com/rustdesk-org/Dash-Chat-2` | `bd6b5b4` | Hỗ trợ truyền nhận tệp, giao diện chat phiên remote thu nhỏ. |
| 2 | `window_manager` | `https://github.com/rustdesk-org/window_manager` | `cf4aef0` | Điều khiển frameless window, widget bong bóng nổi (bubble pill). |
| 3 | `desktop_multi_window` | `https://github.com/rustdesk-org/rustdesk_desktop_multi_window` | `8b774a6` | Mở nhiều cửa sổ remote session độc lập, truyền thông IPC nội bộ. |
| 4 | `flutter_custom_cursor` | `https://github.com/rustdesk-org/flutter_custom_cursor` | `db63b78` | Đồng bộ hình dạng con trỏ chuột từ Host về Client qua RGBA buffer. |
| 5 | `uni_links` | `https://github.com/rustdesk-org/uni_links` (path: `uni_links`) | `f416118` | Xử lý schema `deskagent://` để kết nối nhanh từ trình duyệt. |
| 6 | `texture_rgba_renderer` | `https://github.com/rustdesk-org/flutter_texture_rgba_renderer` | `42797e0` | Native C++ plugin giải nén và render luồng video trực tiếp lên Texture. |
| 7 | `flutter_gpu_texture_renderer` | `https://github.com/rustdesk-org/flutter_gpu_texture_renderer` | `08a471b` | Chia sẻ DirectX/Metal/Vulkan texture zero-copy giúp giảm tải CPU. |
| 8 | `dynamic_layouts` | `https://github.com/rustdesk-org/dynamic_layouts.git` | `24cb884` | Hiển thị dạng lưới tùy biến cho danh bạ thiết bị (Address Book). |

---

## 2. Chiến lược xử lý & Lộ trình thực hiện

### 2.1 Phương án kiến trúc: Vendoring cục bộ (`vendor/flutter/`)
Tương tự như giải pháp đã thành công với 6 Rust crates (WS-1), giải pháp bền vững và độc lập nhất là **Vendoring trực tiếp mã nguồn vào repo**:
- Đưa 8 packages vào thư mục `vendor/flutter_plugins/<package_name>`.
- Trong `flutter/pubspec.yaml`, chuyển đổi khai báo từ `git:` sang `path:`:
  ```yaml
  window_manager:
    path: ../vendor/flutter_plugins/window_manager
  ```
- **Lợi ích:**
  - Loại bỏ hoàn toàn sự phụ thuộc vào mạng Internet lúc `flutter pub get`.
  - Kiểm soát 100% mã nguồn, dễ dàng đổi tên các namespace và identifiers.
  - Đảm bảo tính tái lập (Reproducible Build) mà không sợ repository bên ngoài bị xóa hoặc đổi URL.

### 2.2 Kế hoạch Re-host 6 Binary Assets & 4 GitHub Actions (theo `docs/CI_PROVENANCE.md`)

Bên cạnh Flutter forks, Gate 2 yêu cầu xử lý các tài nguyên mạng bên ngoài trong CI workflow:

1. **Flutter Custom Engine (`.github/workflows/flutter-build.yml:216`):**
   - Thay thế zip custom engine bằng bản build stock Flutter 3.24.5 hoặc lưu trữ engine build độc lập trên hạ tầng DeskAgent CDN/Releases.
2. **Binary Drivers & Utilities (`usbmmidd_v2.zip`, printer drivers):**
   - Re-host lên release storage chính thức của DeskAgent kèm bảng mã băm SHA-256 (`sha256sums`).
   - Duy trì quy trình kiểm tra checksum bắt buộc trước khi giải nén.
3. **GitHub Actions bên thứ ba (`run-on-arch-action`, `install-llvm-action`):**
   - Fork các actions về tổ chức `deskagent-org` hoặc trỏ trực tiếp về repo tác giả gốc uy tín (như `uraimo/run-on-arch-action`), ghim cố định commit SHA.

---

## 3. Quy trình xác thực Clean Build & Tái lập (Verification Steps)

1. **Bước 1 (Pubspec Check):** Quét toàn bộ `flutter/pubspec.yaml` để xác nhận `grep -i "rustdesk-org" flutter/pubspec.yaml` trả về **0 kết quả**.
2. **Bước 2 (Offline Pub Get):** Ngắt kết nối mạng giả lập hoặc xóa cache, chạy `flutter pub get --offline` (hoặc kiểm tra path resolution) xác nhận toàn bộ plugin được nạp từ local vendor.
3. **Bước 3 (Clean Build Test):** Thực hiện `cargo check --locked --lib --features flutter` và build Flutter runner xác nhận không có xung đột phụ thuộc.
4. **Bước 4 (Checksum Verification):** So khớp mã băm SHA-256 của các artifact sau build để chứng minh tính tái lập.

## 4. Ket qua thuc hien 09/10 (vendoring)
- 8 fork da copy vao vendor/flutter_plugins/ (dash_chat_2, window_manager, desktop_multi_window, flutter_custom_cursor, uni_links, texture_rgba_renderer, flutter_gpu_texture_renderer, dynamic_layouts); xoa .git keo theo tu Pub cache; uni_links giu cau truc monorepo, pubspec tro path toi uni_links/uni_links.
- flutter/pubspec.yaml: 0 chuoi rustdesk-org; chuyen 8 khai bao git sang path local.
- Kiem chung: flutter pub get --offline PASS (resolve local vendor); cargo test -p base kx_v2+data_channel 17/17 PASS; cargo check --locked --lib --features flutter PASS giu 17 warnings cu.
- Hash: sha256 gop pubspec.yaml + 18 pubspec vendored = ee32217e96bbde4fc419abc1f049f03411c610a227f2d9b0372af1b9d97d1fbe (19 files, so bo tu dong, khong phai artifact phat hanh).
- Bo sung 09/10: base full 38/38 PASS + 1 ignored (media_transport 5/5, gom relay-envelope loopback tamper-reject); tong file vendored 888 files; sha256 flutter/pubspec.yaml = 8a8e64cf9146cb52c4a29375d369130e1e59bf0a1fb9c4058b4dc81070b79839. Manifest vendor 888 files sha256 = c3d56802c1f0d27275af39c6e98ee35dba2dcbf56dcf0757a337cf442098c26f (path + content).

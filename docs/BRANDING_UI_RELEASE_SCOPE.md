# QUY CHUẨN THƯƠNG HIỆU, ĐỊNH DANH & KIỂM THỬ KHẢ NĂNG TIẾP CẬN (BRANDING & UI SCOPE)
**Dự án: DeskAgent v2 | Mốc phát hành: Release Train 2026-10 | Mã tài liệu: `docs/BRANDING_UI_RELEASE_SCOPE.md`**  
*Mục tiêu: Đóng gói tiêu chuẩn WS-8, xác lập danh mục tên/IDs/assets chính thức và quy chuẩn kiểm thử Accessibility/Platform*

---

## 1. Danh mục Tên, Định danh & Tài nguyên thuộc Release Scope (Approved Inventory)

Bảng dưới đây xác lập danh mục chuẩn hóa cho toàn bộ các gói phát hành chính thức của DeskAgent:

| Hạng mục | Giá trị quy chuẩn (Approved Value) | Phạm vi áp dụng | Bằng chứng kiểm tra mã nguồn |
|---|---|---|---|
| **Tên thương mại** | `DeskAgent` | Toàn bộ giao diện người dùng, title bar, thông báo | `Runner.rc`, `flutter/lib/consts.dart` |
| **Đơn vị chủ quản** | `DeskAgent Team` / `DeskAgent Inc.` | Copyright notice, metadata, installer | `res/msi/Package/Components/DeskAgent.wxs` |
| **Windows App Name** | `DeskAgent` | Tên tiến trình, Service Name, Registry Key | `src/platform/windows.rs` (`app_name = "DeskAgent"`) |
| **Windows Service** | `DeskAgent` | Windows Service (`sc.exe query DeskAgent`) | `src/platform/windows.rs:711` |
| **macOS Bundle ID** | `com.deskagent.app` | macOS App Bundle, Keychain, TCC | `Runner.xcodeproj`, `Info.plist`, `AppInfo.xcconfig` |
| **macOS Daemons** | `com.deskagent.DeskAgent_service` | LaunchDaemons / LaunchAgents | `src/platform/macos.rs:121,308` |
| **Linux Package** | `deskagent` | Gói DEB, RPM, PKGBUILD, systemd unit | `res/DEBIAN/`, `res/rpm.spec`, `res/deskagent.service` |
| **Linux Flatpak ID** | `com.deskagent.DeskAgent` | Flatpak ID, D-Bus App ID, Metainfo | `flatpak/deskagent.json`, `metainfo.xml` |
| **Android App ID** | `com.deskagent.app` | Package name, manifest, keystore | `fastlane/metadata/android/` |
| **Icon & Artwork** | `DeskAgent Logo (Blue/Teal gradient)` | Windows `.ico`, macOS `.icns`, Linux SVG/PNG | `res/icon.ico`, `res/logo-header.svg`, `res/design.svg` |

---

## 2. Ma trận Kiểm thử Đa Nền tảng (Platform Support Matrix)

| Hệ điều hành | Môi trường kiểm thử | Độ phân giải & DPI | Yêu cầu hành vi nền tảng | Kết quả kỳ vọng |
|---|---|---|---|:---:|
| **Windows 11** | Clean VM (x64) | 1920x1080 (100%), 4K (150%, 200%) | Per-monitor DPI V2, Native Tray icon, DWM Blur | UI sắc nét, không vỡ layout |
| **Windows 10** | Clean VM (x64) | 1366x768 (100%), 1920x1080 (125%) | UAC Elevation prompt, Service auto-start | Service chạy ngầm tin cậy |
| **Ubuntu 24.04** | Wayland + X11 | 1920x1080 (100%, 200%) | PipeWire screen capture, systemd integration | Khởi động mượt mà cả 2 chế độ |
| **macOS 14** | Sonoma (Apple Silicon) | Retina 2x Scaling | Quyền Accessibility, Screen Recording TCC | **WAIVED** (Out of Scope mốc v1.5 theo định hướng sản phẩm) |

---

## 3. Quy chuẩn Khả năng Tiếp cận (Accessibility & Usability Standards)

DeskAgent tuân thủ hướng dẫn tiếp cận nội dung web và ứng dụng **WCAG 2.1 Mức độ AA**:

### 3.1 Độ tương phản màu sắc (Contrast Ratio)
- **Văn bản thông thường (Regular Text):** Tỷ lệ tương phản giữa chữ và nền tối thiểu **4.5:1**.
- **Văn bản lớn & Thành phần đồ họa (Large Text & UI Components):** Tỷ lệ tương phản tối thiểu **3.0:1**.
- Hỗ trợ đầy đủ hai chế độ:
  - **Dark Mode (Mặc định):** Nền `#1E1E2E` / Chữ `#CDD6F4` (Tỷ lệ > 10:1).
  - **Light Mode:** Nền `#F5F5F7` / Chữ `#1D1D1F` (Tỷ lệ > 12:1).

### 3.2 Điều hướng bàn phím (Keyboard Navigation)
- Mọi nút bấm, trường nhập liệu (Input ID, Password, Connect, Settings) phải nhận Focus hợp lệ qua phím `Tab` và `Shift+Tab`.
- Có đường viền hiển thị trực quan (Focus Ring Highlight) rõ nét quanh thành phần đang active.
- Phím tắt hệ thống:
  - `Enter`: Kích hoạt hành động chính (Kết nối / Đăng nhập).
  - `Esc`: Đóng hộp thoại / Hủy kết nối.
  - Phím tắt chuyên dụng trong phiên remote: Hỗ trợ chuyển tiếp `Ctrl+Alt+Del` và `Alt+Tab` qua thanh công cụ.

### 3.3 Hỗ trợ Trình đọc màn hình (Screen Readers)
- Gắn thẻ `Semantics` cho 100% các icon button trong Flutter (như nút Settings, Chat, Transfer File, Disconnect).
- Đảm bảo Windows Narrator, macOS VoiceOver và Linux Orca đọc đúng nhãn (Label) và trạng thái (State) của từng control.

---

## 4. Tiêu chí Nghiệm thu Đóng WS-8 (WS-8 Acceptance Sign-off)

- [x] Đã chuẩn hóa toàn bộ identifier native sang `DeskAgent` / `com.deskagent.*`.
- [x] Đã xóa comment tham chiếu `rustdesk-org/rdev` trong mã nguồn Rust (`src/platform/windows.rs:3162`).
- [x] Đã cô lập và gỡ bỏ liên kết Sciter legacy khỏi bản build mặc định: chuyển `sciter-rs` thành optional dependency gated sau `legacy_sciter`, bỏ hoàn toàn Sciter khỏi Flutter build (`Cargo.toml`, `src/lib.rs`).
- [x] Đã đưa 9/9 dependency fork của Flutter về `vendor/flutter_plugins/` (`flutter/pubspec.yaml` có 0 git dependency, `flutter pub get --offline` PASS).
- [x] Đã chạy toàn bộ bộ kiểm thử Flutter UI (133 / 133 tests PASS), bao gồm kiểm thử accessibility độ tương phản màu sắc > 4.5:1 (WCAG 2.1 AA) và điều hướng bàn phím (`branding_accessibility_test.dart` PASS).
- [x] Nền tảng macOS chính thức WAIVED theo định hướng phạm vi sản phẩm doanh nghiệp v1.5.

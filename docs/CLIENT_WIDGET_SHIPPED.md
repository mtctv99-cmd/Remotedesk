# CLIENT WIDGET ĐANG CHẠY — PIL 86×40 (pre-Go, build 05/10/2026)

Nguồn sự thật: **build chạy thật** `Remote\DeskAgent-extracted` (exe + `data\app.so` 05/10/2026),
ảnh chụp `pill-old-click.png`, `pill_menu_open.png`, `verified_single_pill.png` (workspace root),
và báo cáo HWND trong `docs/BAO_CAO_TIEN_DO.md:34`.

Đây là bản client **đang cài trên Win11 host** (`C:\Program Files\DeskAgent`, 22/10/2026).
Mã Dart của nó **không có trong git** (chưa từng commit, không có trong dangling blob/mirror).

---

## 1. Trạng thái thu gọn — viên thuốc

| Thuộc tính | Giá trị | Nguồn |
|---|---|---|
| Kích thước cửa sổ | **86 × 40** | HWND 2464,1346 86×40 (BAO_CAO_TIEN_DO.md:34) |
| Neo | góc phải dưới, margin phải ~10, đáy ~6 (trên taskbar) | đo từ rect 2464,1346 @2560×1440 |
| Nền | `#202020` | verified_single_pill.png |
| Viền | trắng 12% (hairline) | như panel |
| Radius | **20** (viên thuốc) | như trên |
| Icon | headphones `#60CDFF`, 17px | ảnh |
| Text | `Hỗ trợ` `#F4F4F5`, 12.5, w600 | ảnh |
| Always-on-top | bật | hành vi đã xác nhận |
| Hình dạng cửa sổ | frameless (không caption) | 86 < min-track 136 chỉ đạt được khi gỡ style bits |

Hành vi: **click** → mở panel; **chuột phải** → menu "Đóng (Chạy ngầm)".

## 2. Panel mở ra — 380 × 96

| Vùng | Giá trị | Nguồn |
|---|---|---|
| Cửa sổ | 380 × 96, radius 12, nền `#202020`, viền trắng 12% | pill-old-click.png |
| Padding | 12 ngang, 10 trên/dưới; hàng 1 cao ~38, gap 6, hàng 2 ~32 | ảnh |
| Hàng 1 trái | icon monitor 16 `#60CDFF` | ảnh |
| Chip IP | `IP` badge nền `#60CDFF` chữ `#0B0B0B` + địa chỉ IP + `|` + mật khẩu, mono 11.5 `#F4F4F5`, nền chip `#2A2A2E` radius 6 | ảnh |
| Hàng 1 phải | pill `Hỗ trợ` (headphones 14 + text 11.5), radius 14, viền trắng 12% → **thu về viên thuốc** | ảnh |
| Hàng 2 | icon monitor 15 `#A1A1AA` + ô nhập ID mono 13 `#F4F4F5` (placeholder "Nhập ID máy cần điều khiển...") | ảnh |
| Nút Kết nối | nền `#60CDFF`, chữ **`#0B0B0B`** w700 12, radius 6, cao 30, icon headphones 13 | ảnh |

## 3. Menu chuột phải

Panel acrylic `#2A2A2E`/`#202020` radius 8, cao ~34, rộng ~168: `× Đóng (Chạy ngầm)` —
đóng cửa sổ, app chạy ngầm cùng tray. Nguồn `pill_menu_open.png` + phiên làm việc 02/10.

## 4. Bài học Win32 (bắt buộc khi dựng lại bằng Flutter)

1. `window_manager.setAsFrameless()` một mình **không đủ**: `GWL_STYLE` vẫn còn
   `WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX|WS_MAXIMIZEBOX` → Windows kẹp min-track
   **136×40**, viên thuốc 86 bị tràn nền trong suốt.
2. Giữ `WS_THICKFRAME`: gỡ luôn nó làm **surface Flutter chết** (window trong suốt đen).
   Chỉ gỡ 4 bit caption là đủ.
3. `WS_EX_NOACTIVATE` làm click không bao giờ tới Flutter → phải gỡ.
4. Đổi kích thước bằng `SetWindowPos` thô làm engine không nhận WM_SIZE mới →
   vùng vẽ đen; phải dùng `windowManager.setSize`.
5. Style strip phải chạy **sau khi cửa sổ đã hiện** (~900ms), không chạy trước show.

## 5. Quyết định deploy (22/10/2026)

- Win11 host (và chuẩn dùng cho client mới) chạy **build pre-Go 05/10** — giao diện
  viên thuốc, đã nghiệm thu (BAO_CAO_TIEN_DO.md P4 = 10/10).
- Bản cài cũ 12/10 (kèm `daserver.exe`/`damanager.exe` nhánh Go) được dời vào
  `Program Files\DeskAgent\_legacy\` / `_old-*\` trước khi thay.
- Dựng lại trên Flutter mới (repo HEAD, nhánh `main`, commit `fae6b6cf8`…`bfc5f703f`)
  đã đạt pill + panel + click + startup=pill; khi cần nâng client mà vẫn giữ giao diện,
  xuất phát từ nhánh đó, **không** bỏ trạng thái pill đi.

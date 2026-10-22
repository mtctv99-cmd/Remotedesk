# CONTRACT UI DESIGN — DeskAgent (Flutter)

Hợp đồng thiết kế chốt số đo cho kỹ sư sửa mã Flutter. Nguồn sự thật = mockup HTML trong `C:\Users\chu.mai\Desktop\Remote\`.

Quy ước:
- Mọi giá trị dưới đây **chép từ mockup**. Không có giá trị nào tự đặt ra. Chỗ mockup không nói → **TBD** (không đoán).
- `file:dòng` trỏ vào mockup. `remote-session-goc.html` và `DeskAgent/demo-remote-session.html` đã đối chiếu bằng `cmp -s` → IDENTICAL, dùng chung số dòng được.
- 1px CSS ≈ 1 logical px Flutter (giả định; mockup vẽ ở CSS px).
- Font mockup: `"Segoe UI Variable Text", "Segoe UI Variable", "Segoe UI", ...` (client-widget-goc.html:62). Số ID/mật khẩu: Consolas, monospace (client-widget-goc.html:364,386).

---

## 1. Bảng màu

### 1.1 Bảng nền tảng (popup-windows-goc.html `:root`, dòng 8–25) — Fluent Dark Win11

| Token | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| accent | `#60cdff` | popup-windows-goc.html:9 |
| accent-hover | `#7cd5ff` | popup-windows-goc.html:10 |
| accent glow | `rgba(96, 205, 255, 0.35)` | popup-windows-goc.html:11 |
| nền window (acrylic base) | `#202020` | popup-windows-goc.html:12 |
| card / surface | `#272727` | popup-windows-goc.html:13 |
| surface subtle | `#2d2d2d` | popup-windows-goc.html:14 |
| hover overlay | `rgba(255, 255, 255, 0.08)` | popup-windows-goc.html:15 |
| active overlay | `rgba(255, 255, 255, 0.05)` | popup-windows-goc.html:16 |
| viền chuẩn | `rgba(255, 255, 255, 0.12)` | popup-windows-goc.html:17 |
| text chính | `#f4f4f5` | popup-windows-goc.html:18 |
| text phụ | `#a1a1aa` | popup-windows-goc.html:19 |
| danger | `#f87171` | popup-windows-goc.html:20 |
| danger bg | `rgba(248, 113, 113, 0.12)` | popup-windows-goc.html:21 |
| success | `#34d399` | popup-windows-goc.html:22 |
| warning | `#fbbf24` | popup-windows-goc.html:23 |
| radius window | `8px` | popup-windows-goc.html:24 |

### 1.2 Token remote session (remote-session-goc.html `:root`, dòng 8–19)

| Token | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| nền titlebar/window | `#202020` | remote-session-goc.html:9 |
| subtle | `#2b2b2b` | remote-session-goc.html:10 |
| **viền 8%** (`--win11-border`) | `rgba(255, 255, 255, 0.08)` | remote-session-goc.html:11 |
| accent | `#60cdff` | remote-session-goc.html:12 |
| text chính | `#ffffff` | remote-session-goc.html:13 |
| text phụ | `#d1d5db` | remote-session-goc.html:14 |
| close hover (danger) | `#c42b1c` | remote-session-goc.html:15 |
| btn hover | `rgba(255, 255, 255, 0.06)` | remote-session-goc.html:16 |
| btn active | `rgba(255, 255, 255, 0.10)` | remote-session-goc.html:17 |
| titlebar height | `32px` | remote-session-goc.html:18 |

### 1.3 Token client widget (client-widget-goc.html `:root` dòng 8–38, dark-mode dòng 40–56)

| Token | Light | Dark (`body.dark-mode`) | Nguồn (file:dòng) |
|---|---|---|---|
| nền body | `#f3f3f3` | `#181818` | client-widget-goc.html:11 / :42 |
| nền window | `#f9f9f9` | `#202020` (override riêng `.client-window`: `#202022`) | client-widget-goc.html:12 / :43, :155-157 |
| surface subtle | `rgba(0, 0, 0, 0.025)` | `rgba(255, 255, 255, 0.035)` | client-widget-goc.html:13 / :44 |
| surface card | `#ffffff` | `rgba(255, 255, 255, 0.05)` | client-widget-goc.html:14 / :45 |
| surface hover | `#fcfcfc` | `rgba(255, 255, 255, 0.08)` | client-widget-goc.html:15 / :46 |
| viền 7% (`--border-subtle`) | `rgba(0, 0, 0, 0.07)` | `rgba(255, 255, 255, 0.07)` | client-widget-goc.html:16 / :47 |
| viền 14% (`--border-strong`) | `rgba(0, 0, 0, 0.14)` | `rgba(255, 255, 255, 0.14)` | client-widget-goc.html:17 / :48 |
| accent cam | `#f97316` | giữ nguyên | client-widget-goc.html:20 |
| cam đậm | `#ea580c` | — | client-widget-goc.html:21 |
| cam gradient | `linear-gradient(135deg, #fb923c 0%, #ea580c 100%)` | — | client-widget-goc.html:24 |
| accent xanh | `#0284c7` | — | client-widget-goc.html:27 |
| xanh đậm | `#0369a1` | — | client-widget-goc.html:28 |
| xanh gradient | `linear-gradient(135deg, #0284c7 0%, #0369a1 100%)` | — | client-widget-goc.html:31 |
| text chính | `#1c1c1c` | `#ffffff` | client-widget-goc.html:34 / :53 |
| text phụ | `#5c5c5c` | `rgba(255, 255, 255, 0.65)` | client-widget-goc.html:35 / :54 |
| text mờ (tertiary) | `#8a8a8a` | `rgba(255, 255, 255, 0.45)` | client-widget-goc.html:36 / :55 |
| success (`--green`) | `#10b981` | `#10b981` | client-widget-goc.html:37 |

### 1.4 Token design system tổng (demo-all-screens.html `:root`, dòng 8–46)

| Token | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| accent (MyTheme.accent) | `#0071FF` | demo-all-screens.html:14, :1477 |
| accent-teal | `#14b8a6` | demo-all-screens.html:15 |
| SvcStatus.ready (online) | `#32BEA6` | demo-all-screens.html:16, :1484 |
| amber (connecting) | `#F59E0B` | demo-all-screens.html:17, :1491 |
| Critical/Lỗi | `#E04F5F` | demo-all-screens.html:18, :1498 |
| orange brand | `#f97316` | demo-all-screens.html:19 |
| viền 8% | `rgba(255, 255, 255, 0.08)` | demo-all-screens.html:20 |
| dark scaffold bg | `#18191E` | demo-all-screens.html:35, :1505 |
| dark card | `#24252B` | demo-all-screens.html:31, :1512 |
| dark text | `#f1f5f9` | demo-all-screens.html:32, :1513 (label) |
| dark text phụ | `#94a3b8` | demo-all-screens.html:33 |
| light bg | `#ffffff` | demo-all-screens.html:23 |
| light card/grayBg | `#EFEFF2` | demo-all-screens.html:24, :1519 |
| light text | `#1e293b` | demo-all-screens.html:25 |
| light text phụ | `#64748b` | demo-all-screens.html:26 |

### 1.5 Yêu cầu chốt cho các ô bắt buộc

| Ô | Giá trị chốt | Nguồn (file:dòng) |
|---|---|---|
| accent | `#60cdff` (surface thì Win11 Fluent). Client widget dùng cam `#f97316` / xanh `#0284c7` cho nút hành động | popup-windows-goc.html:9; client-widget-goc.html:20,27,24,31 |
| nền acrylic | BG `rgba(32, 32, 32, 0.92)` + `backdrop-filter: blur(24px) saturate(140%)`; dialog đậm hơn `rgba(30, 30, 30, 0.96)` | popup-windows-goc.html:336-337; remote-session-goc.html:297,305; popup-windows-goc.html:772 |
| warning | `#fbbf24` | popup-windows-goc.html:23; remote-session-goc.html:1352 |
| success | `#34d399` | popup-windows-goc.html:22; remote-session-goc.html:1351 |
| danger | `#f87171` (text/badge). Nút close hover: `#c42b1c`. Unread badge: `#ef4444` | popup-windows-goc.html:20; remote-session-goc.html:15,1293 |
| text chính | `#f4f4f5` (Win11 surface) / `#ffffff` (remote titlebar) | popup-windows-goc.html:18; remote-session-goc.html:13 |
| text phụ | `#a1a1aa` (Win11 surface) / `#d1d5db` (remote) | popup-windows-goc.html:19; remote-session-goc.html:14 |
| viền 8% | `rgba(255, 255, 255, 0.08)` | remote-session-goc.html:11; demo-all-screens.html:20 |
| viền 12% | `rgba(255, 255, 255, 0.12)` | popup-windows-goc.html:17 |

---

## 2. Cửa sổ widget client (`client-widget-goc.html`)

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| width | `380px` | client-widget-goc.html:125 |
| height thu gọn | `140px` | client-widget-goc.html:126 |
| height mở rộng (chat) | `calc(100vh - 58px)`, min `480px`, max `calc(100vh - 20px)` | client-widget-goc.html:139-141 |
| transition height | `0.28s cubic-bezier(0.16, 1, 0.3, 1)` | client-widget-goc.html:135 |
| border-radius | `12px` (góc) | client-widget-goc.html:128 |
| nền | `--bg-window`; dark: `#202022` | client-widget-goc.html:127, :156 |
| viền | `1px solid rgba(0,0,0,0.07)` (dark 7% trắng) | client-widget-goc.html:129, :47 |
| box-shadow thu gọn | `0 14px 35px -10px rgba(0,0,0,0.12), 0 0 1px 1px rgba(0,0,0,0.04)` | client-widget-goc.html:130 |
| box-shadow mở rộng | `0 22px 50px -10px rgba(0,0,0,0.22), 0 0 1px 1px rgba(0,0,0,0.05)` | client-widget-goc.html:142 |
| margin neo góc đáy phải (`.docked-right`) | `align-self: flex-end; margin-right: 12px;` + phẳng 2 góc phải (`border-top-right-radius: 0; border-bottom-right-radius: 0`) | client-widget-goc.html:149-154 |
| margin bottom | **TBD** (không có margin-bottom; body padding `8px 16px`) | client-widget-goc.html:76 |
| margin top → bottom gap | thu gọn `140px` → mở `100vh-58px`; chênh `58px` = 8px top pad + ~50px (vùng top-controls) — **chỉ số tổng 58px là chốt** | client-widget-goc.html:139, :76 |
| overflow | `visible` (để dropdown bật ra ngoài khi thu gọn) | client-widget-goc.html:133 |
| header height | `42px` (`padding: 8px 12px 2px 12px`) | client-widget-goc.html:160-166 |
| logo | `28×28`, radius `8px` | client-widget-goc.html:173-175 |
| status indicator (chấm logo) | `7×7`, viền `1.5px`, `#10b981` | client-widget-goc.html:200-205 |
| nút "Gửi IT" | height `24px`, radius `5px`, padding `3px 7px`, font `11px/700` | client-widget-goc.html:398-406 |
| section remote padding | `3px 12px 10px 12px`; border-bottom `1px solid var(--border-subtle)` | client-widget-goc.html:491-494 |
| **connect bar** | height `36px`, radius `8px`, border `1px solid rgba(0,0,0,0.14)` (dark 14%), padding `0 4px 0 10px`, bg `--surface-card`, shadow `0 1px 3px rgba(0,0,0,0.04)` | client-widget-goc.html:499-507 |
| connect bar hover / focus | hover border `rgba(2,132,199,0.4)`; focus border `#0284c7` + ring `0 0 0 2px rgba(2,132,199,0.15)` | client-widget-goc.html:510-517 |
| input font | `13px/600`, Consolas; placeholder `11.5px` regular | client-widget-goc.html:523-541 |
| nút "Kết nối" | height `26px`, radius `5px`, padding `0 11px`, font `11.5px/700`, bg xanh gradient, chữ `#ffffff` | client-widget-goc.html:544-552 |
| nút hành động lớn (`.btn-share-all`) | height `38px`, radius `8px`, font `13px/700`, cam gradient, chữ `#ffffff`, shadow `0 4px 14px rgba(234,88,12,0.25)` | client-widget-goc.html:443-457 |
| recent-dropdown vị trí | `top: calc(100% + 2px); left: 12px; right: 12px` | client-widget-goc.html:571-574 |
| recent-dropdown style | radius `8px`, border `1px solid 14%`, shadow `0 16px 36px -4px rgba(0,0,0,0.28), 0 0 1px 1px rgba(0,0,0,0.08)`, anim `0.16s` | client-widget-goc.html:576-581 |
| recent-dd header | padding `6px 12px`, font `10.5px/700`, uppercase, letter-spacing `0.5px`, text `--text-subtle` | client-widget-goc.html:587-599 |
| recent-dd list | max-height `140px`, padding `4px`, gap `2px`, scrollbar `4px` | client-widget-goc.html:614-630 |
| recent-dd item | padding `6px 8px`, radius `8px`, icon `26×26` radius `6px` | client-widget-goc.html:634-659 |
| scrollbar chung | width `4px`, thumb `rgba(148,163,184,0.3–0.4)` | client-widget-goc.html:721-728, 861-867 |
| chat bubble | padding `8px 11px`, radius `12px`, font `12px/1.45`, max-width `90%` | client-widget-goc.html:870-922 |
| chat composer | padding `4px 12px 10px 12px` | client-widget-goc.html:1010 |
| about modal (trong widget) | max-width `340px`, radius `12px`, overlay `rgba(0,0,0,0.45)` + blur `4px` | client-widget-goc.html:1601-1621 |

Ghi chú: `popup-windows-goc.html` có biến thể widget khác — "compact card" `380px` wide, header `44px`, input/connect `34px`, radius `8px`, acrylic `rgba(32,32,32,0.92)` (popup-windows-goc.html:334-422). Đây là biến thể thứ 2, không phải `.client-window`. Xem mục Lưu ý mâu thuẫn.

---

## 3. Dialog / popup / toast (`popup-windows-goc.html`)

### 3.1 Dialog card (`.modal-dialog-card` + `.modal-*`)

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| card width | `340px` | popup-windows-goc.html:771 |
| padding | `16px` | popup-windows-goc.html:775 |
| border-radius | `8px` | popup-windows-goc.html:774 |
| border | `1px solid rgba(255, 255, 255, 0.12)` | popup-windows-goc.html:773, :17 |
| nền | `rgba(30, 30, 30, 0.96)` | popup-windows-goc.html:772 |
| box-shadow | `0 20px 50px rgba(0,0,0,0.7)` | popup-windows-goc.html:779 |
| khoảng cách nội bộ (gap) | `12px` | popup-windows-goc.html:778 |
| tiêu đề | `13px`, weight `600`, `#ffffff`, icon `16×16`, gap `8px` | popup-windows-goc.html:781-787, :1094 |
| thân (body text) | `11.5px`, màu `#a1a1aa`, line-height `1.45` | popup-windows-goc.html:789-793 |
| input | height `32px`, radius `4px`, bg `#202025`, border 12%, font `12px`, padding `0 10px`; focus border accent | popup-windows-goc.html:794-807 |
| footer | `justify-content: flex-end`, gap `8px`, margin-top `4px` | popup-windows-goc.html:808-813 |
| nút (chung) | padding `6px 14px`, radius `4px`, font `11.5px` | popup-windows-goc.html:814-821 |
| nút primary | bg `#60cdff`, không border, chữ `#000000`, weight `600` | popup-windows-goc.html:822-827 |
| nút secondary | bg `#2a2a2e`, border `1px solid 12%`, chữ `#e2e8f0`, weight `500` | popup-windows-goc.html:828-832, :818 |

### 3.2 Toast (`.fluent-toast-item`)

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| container width | `330px`, gap `8px` | popup-windows-goc.html:837-842 |
| nền | `rgba(32, 32, 32, 0.94)` | popup-windows-goc.html:844 |
| viền | `1px solid rgba(255,255,255,0.12)` | popup-windows-goc.html:845 |
| radius | `6px` | popup-windows-goc.html:846 |
| padding | `8px 12px` | popup-windows-goc.html:847 |
| font | `11.5px` | popup-windows-goc.html:851 |
| box-shadow | `0 6px 20px rgba(0,0,0,0.45)` | popup-windows-goc.html:852 |
| viền trái info | `3px solid #60cdff` | popup-windows-goc.html:854 |
| viền trái success | `3px solid #34d399` | popup-windows-goc.html:855 |
| viền trái warn | `3px solid #fbbf24` | popup-windows-goc.html:856 |
| viền trái error | `3px solid #f87171` | popup-windows-goc.html:857 |

### 3.3 Các popup khác (popup-windows-goc.html)

| Popup | Số đo | Nguồn (file:dòng) |
|---|---|---|
| Incoming connection request (frameless) | width `320px`, padding `12px`, gap `10px`, radius `8px`, nền `rgba(32,32,32,0.94)` + blur `28px`, shadow `0 20px 48px rgba(0,0,0,0.65)` | popup-windows-goc.html:435-447 |
| Permission grid | 4 cột, gap `6px`, padding `8px`, nút height `42px`, radius `5px`, font `8.5px`; active bg `rgba(96,205,255,0.18)`, border `rgba(96,205,255,0.45)` | popup-windows-goc.html:491-519 |
| Accept / Cancel | height `32px`, radius `4px`, font `11.5px`; accept bg accent chữ `#000`; cancel bg `#2a2a2a` chữ `#d4d4d8` | popup-windows-goc.html:524-544 |
| Session active bar | width `340px`, radius `20px`, padding `6px 12px`, border `1px solid rgba(16,185,129,0.35)` | popup-windows-goc.html:549-560 |
| Nút Disconnect | padding `3px 10px`, radius `12px`, bg `rgba(239,68,68,0.15)`, border `rgba(239,68,68,0.4)`, chữ `#f87171`, font `10.5px/600` | popup-windows-goc.html:574-584 |
| Client chat popup (biến thể) | `300×320`, header `32px`, bubble `6px 9px` radius `6px`, input height `28px` | popup-windows-goc.html:587-660 |
| IT toolbar box | width `380px`, padding `6px 10px`, radius `8px`, nút `32×32`, separator `1px × 18px` | popup-windows-goc.html:665-704 |
| IT tools window (biến thể 4 tab) | width `380px`, **height `420px` (chỉ là badge, CSS không set height)** — xem TBD | popup-windows-goc.html:709-718, :1057 |

---

## 4. Màn hình remote session (`remote-session-goc.html`)

### 4.1 Titlebar

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| titlebar height | `32px` | remote-session-goc.html:18, :58, :86 |
| titlebar màu | `#202020` | remote-session-goc.html:87 |
| viền dưới | `1px solid rgba(255, 255, 255, 0.08)` | remote-session-goc.html:88 |
| shadow | `0 4px 16px rgba(0,0,0,0.5)` | remote-session-goc.html:92 |
| app icon | `15×15`, accent | remote-session-goc.html:134-138 |
| tên phiên | `12px/500`, `#ffffff` | remote-session-goc.html:140-145 |
| badge P2P | font `10px` Consolas, `#4ade80`, bg `rgba(74,222,128,0.12)`, border `rgba(74,222,128,0.25)`, radius `4px`, padding `1px 6px` | remote-session-goc.html:146-154 |
| nút tool | height `24px`, padding `0 7px`, radius `4px`, font `11.5px`, gap `2px`; icon-only `26px` | remote-session-goc.html:157-183 |
| nút tool hover/active | hover bg `rgba(255,255,255,0.06)`; active bg `rgba(255,255,255,0.10)`; selected bg `rgba(96,205,255,0.18)` border `rgba(96,205,255,0.3)` | remote-session-goc.html:184-196 |
| separator | `1px × 14px`, margin `0 4px` | remote-session-goc.html:197-202 |
| icon SVG nội dung | `14×14`, stroke-width `1.8` | remote-session-goc.html:205-213 |

### 4.2 Caption button

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| kích thước | `46 × 32px` (width `46px`, height `var(--titlebar-h)`) | remote-session-goc.html:228-231 |
| màu mặc định | trong suốt, chữ `#d1d5db` | remote-session-goc.html:233-234 |
| hover | bg `rgba(255,255,255,0.06)`, chữ `#fff` | remote-session-goc.html:241-244 |
| **close hover** | bg `#c42b1c`, chữ `#fff` | remote-session-goc.html:245-248 |
| glyph | `10×10` viewBox `0 0 10 10`, stroke-width `1.2` | remote-session-goc.html:1704-1719 |

### 4.3 Ẩn/hiện titlebar

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| **trigger zone** | `top: 0; left: 0; width: 100%; height: 8px; z-index: 95` | remote-session-goc.html:46-53 |
| auto-hide transform | `translateY(-100%)`, transition `0.22s cubic-bezier(0.1, 0.9, 0.2, 1)` | remote-session-goc.html:61, :71-76 |
| **handle** | `bottom: -14px` (treo dưới titlebar), height `14px`, padding `0 16px`, radius `0 0 6px 6px`, border trừ cạnh trên, shadow `0 2px 8px rgba(0,0,0,0.4)`, icon `10×10` | remote-session-goc.html:98-115, :1728 |
| handle ẩn khi pinned | `display: none` | remote-session-goc.html:122-124 |
| mặc định | `.pinned` | remote-session-goc.html:1660 |

### 4.4 Cửa sổ Tools

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| vị trí mặc định | `top: 54px; left: calc(50% - 290px)` | remote-session-goc.html:293-294 |
| **kích thước** | **`580 × 420px`** | remote-session-goc.html:295-296 |
| nền | `rgba(36, 36, 36, 0.88)` + `blur(24px) saturate(140%)` | remote-session-goc.html:297, :305 |
| border / radius | `1px solid rgba(255,255,255,0.08)`, radius `8px` | remote-session-goc.html:298-299 |
| shadow | `0 18px 48px rgba(0,0,0,0.7), 0 0 1px rgba(255,255,255,0.2)` | remote-session-goc.html:300 |
| resize | `both`, min `440 × 280`, max `95vw × 90vh` | remote-session-goc.html:307-311 |
| anim mở | `win11Pop 0.16s`, từ `scale(0.96) translateY(-8px)` | remote-session-goc.html:312-326 |
| titlebar cửa sổ tools | height `36px`, bg `#1c1c1c`, border-bottom `1px solid rgba(255,255,255,0.08)`, padding-left `8px`, cursor move | remote-session-goc.html:329-340 |
| caption btn tools | `38 × 36px`; close hover `#c42b1c` | remote-session-goc.html:351-370 |
| tab button | padding `4px 10px`, radius `5px`, font `12px`, gap `3px`; active bg `rgba(255,255,255,0.1)` border `rgba(255,255,255,0.12)` chữ accent weight `500` | remote-session-goc.html:341-346, :371-394 |
| body | padding `12px`, bg `#181818` | remote-session-goc.html:397-402 |

### 4.5 Chat popup phía client (`.client-chat-win`)

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| vị trí | `bottom: 24px; right: 24px` | remote-session-goc.html:1092-1093 |
| **kích thước** | **`320 × 380px`** | remote-session-goc.html:1094-1095 |
| nền | `rgba(32,32,32,0.88)` + blur `24px` saturate `140%` | remote-session-goc.html:1096, :1104 |
| border / radius / shadow | 8%, `8px`, `0 16px 40px rgba(0,0,0,0.65), 0 0 1px rgba(255,255,255,0.12)` | remote-session-goc.html:1097-1099 |
| header | height `34px`, bg `#1c1c1c`, padding `0 8px 0 12px` | remote-session-goc.html:1114-1124 |
| nút header | `26 × 24px`, radius `4px`, close hover `#c42b1c` | remote-session-goc.html:1145-1164 |
| body | padding `10px`, gap `8px`, bg `#181818` | remote-session-goc.html:1166-1174 |
| bubble | max-width `85%`, padding `7px 10px`, radius `6px`, font `11.5px` | remote-session-goc.html:1183-1215 |
| dock button (thu nhỏ) | `bottom/right: 24px`, padding `7px 14px`, radius `20px`, font `11.5px/500`, blur `24px` | remote-session-goc.html:1254-1274 |
| unread badge | bg `#ef4444`, font `10px/700`, padding `1px 6px`, radius `10px`, border `1px solid rgba(255,255,255,0.2)` | remote-session-goc.html:1292-1301 |
| mặc định | `hidden` khi vừa vào phiên | remote-session-goc.html:1748 |

### 4.6 Danh sách tab Tools (cố định 4 tab, thứ tự)

| # | Nhãn | Icon | Nguồn (file:dòng) |
|---|---|---|---|
| 1 | Sự kiện (mặc định active) | document | remote-session-goc.html:1798-1801 |
| 2 | Deploy | box/package | remote-session-goc.html:1802-1805 |
| 3 | Chat | speech bubble | remote-session-goc.html:1806-1809 |
| 4 | Trợ lý AI (icon màu `#c084fc`) | sparkle | remote-session-goc.html:1810-1813 |

Titlebar tools có: icon accent ở left, 4 tab, rồi 2 nút caption (minimize: `toggleToolsWindow`, close: `toggleToolsWindow`) (remote-session-goc.html:1815-1822).
Hành vi: chuyển tab `chat` tự mở client chat (remote-session-goc.html JS `switchToolsTab`).

### 4.7 Toast trên màn remote

| Thuộc tính | Giá trị | Nguồn (file:dòng) |
|---|---|---|
| container | `fixed; bottom: 24px; left: 24px`, column-reverse, gap `8px`, max-width `380px` | remote-session-goc.html:1304-1314 |
| item | bg `rgba(32,32,32,0.92)`, border 8%, radius `8px`, padding `10px 12px`, blur `24px` | remote-session-goc.html:1315-1323 |
| icon | `16×16`; info accent / success `#34d399` / warn `#fbbf24` / error `#f87171` | remote-session-goc.html:1344-1353 |
| title / msg | `11.5px/600 #fff`; `11px #d1d5db` lh `1.35` | remote-session-goc.html:1360-1368 |
| anim | `toastSlideIn 0.22s` | remote-session-goc.html:1327-1343 |

---

## 5. TBD — mockup KHÔNG quy định (không đoán số)

| Hạng mục | Lý do TBD |
|---|---|
| Hành vi auto-collapse widget | Không có timer/JS nào tự thu gọn `.client-window`; chỉ có collapse khi bấm nút (client-widget-goc.html `collapseChatWindow`). Thời gian/điều kiện tự thu gọn: không có. |
| Hành vi auto-hide titlebar theo thời gian | Chỉ có hover-based (trigger zone + hover). Không có timeout ẩn sau khi rời hover (remote-session-goc.html:79-83). |
| Bong bóng tròn (floating bubble) "chính thức" | Chỉ có demo trong showcase: `50 × 50`, `rgba(32,32,32,0.9)`, viền 12%, nút X `16×16` (popup-windows-goc.html:293-331). Không xuất hiện trong `.client-window`. Vị trí neo màn hình: **TBD**. |
| Chiều cao cố định của tools window ở biến thể popup `380×420` | `420px` chỉ là text badge; CSS `.it-tools-window-card` không set height (popup-windows-goc.html:709-718, :1057). |
| Margin-bottom widget khi dock góc đáy phải | Chỉ có `margin-right: 12px` + body padding; không có margin-bottom khai báo. |
| Kích thước / vị trí cửa sổ client-chat popup ở biến thể popup (`300×320`) vs remote (`320×380`) | Hai số khác nhau, không có ghi chú cái nào là chuẩn — xem mâu thuẫn. |
| Độ mờ nền (opacity) của acrylic khi không có compositor | Chỉ có giá trị `backdrop-filter`; fallback Flutter cụ thể: TBD. |
| Bảng màu Light mode cho dialog/popup | Chỉ `client-widget-goc.html` có light mode; popup-windows-goc.html và remote-session-goc.html không có light. Light cho dialog/toast/remote: TBD. |
| Animation chuyển trang Flutter, curve cho expand widget ở Flutter | Chỉ có CSS transition; mapping Flutter (Duration/Curve) quyết định bởi kỹ sư — không có trong mockup. |
| Focus ring / trạng thái disabled của nút primary/secondary | Mockup chỉ có `:focus` cho input (border accent), không có disabled style cho `.modal-btn`. |
| Hover/pressed state cho desktop (MouseRegion) | Mockup có `:hover`; mapping Flutter: TBD. |
| Kích thước font icon overlay `client-unread-badge` khi >9 | Chỉ có số `1`; truncation format: TBD. |
| Nền viewport video (`#remote-viewport`) khi có stream | Mockup chỉ có placeholder `#000` và hướng dẫn nhúng; letterbox/scale mode: TBD. |

---

## Lưu ý mâu thuẫn

### A. Branding doc vs mockup (KHÔNG tự sửa file branding)

`DeskAgent/docs/BRANDING_UI_RELEASE_SCOPE.md:45`:
> **Dark Mode (Mặc định):** Nền `#1E1E2E` / Chữ `#CDD6F4`

`DeskAgent/docs/BRANDING_UI_RELEASE_SCOPE.md:46`:
> **Light Mode:** Nền `#F5F5F7` / Chữ `#1D1D1F`

Không khớp với mockup:
- Dark nền: mockup dùng `#202020` (popup-windows-goc.html:12; remote-session-goc.html:9) và `#18191E` (demo-all-screens.html:35). Không có `#1E1E2E` ở đâu.
- Dark chữ: mockup dùng `#f4f4f5` / `#ffffff` / `#f1f5f9`. Không có `#CDD6F4`.
- Light nền: mockup widget dùng `#f9f9f9` (client-widget-goc.html:12) / `#ffffff` (demo-all-screens.html:23). Không có `#F5F5F7`.
- Light chữ: mockup dùng `#1c1c1c` (client-widget-goc.html:34) / `#1e293b` (demo-all-screens.html:25). Không có `#1D1D1F`.

→ Cần người sở hữu branding chốt nguồn chuẩn. Hợp đồng này theo mockup (nguồn sự thật theo yêu cầu của task). **Chưa sửa `BRANDING_UI_RELEASE_SCOPE.md`.**

### B. Viền 8% vs 12%

`remote-session-goc.html:11` và `demo-all-screens.html:20` = `rgba(255,255,255,0.08)`. `popup-windows-goc.html:17` = `0.12`. `client-widget-goc.html:47` dark = `0.07`; `:48` strong = `0.14`. Ba giá trị cùng gọi "viền chuẩn". Hợp đồng: dùng `0.08` cho surface remote/tools/chat popup; `0.12` cho dialog/toast/input ở `popup-windows-goc`; `0.07` là "subtle" của client widget (khác tên, không phải mâu thuẫn trực tiếp nhưng dễ nhầm).

### C. Text phụ

`#a1a1aa` (popup-windows-goc.html:19) vs `#d1d5db` (remote-session-goc.html:14) vs `#94a3b8` (demo-all-screens.html:33) vs `rgba(255,255,255,0.65)` (client-widget-goc.html:54). Tên "text phụ" dùng cho nhiều giá trị trong các surface khác nhau — không phải token chung.

### D. Accent

`#60cdff` (Win11 surface: popup-windows-goc.html:9, remote-session-goc.html:12) vs `#0071FF` (design tokens: demo-all-screens.html:14) vs `#f97316`/`#0284c7` (client widget: client-widget-goc.html:20,27). Ba hệ accent song song.

### E. Client chat popup kích thước

`popup-windows-goc.html:587-589` = `300 × 320`. `remote-session-goc.html:1094-1095` = `320 × 380`. Không có ghi chú cái nào thay cái nào.

### F. Tools window: 4 tab thống nhất, kích thước khác nhau

- `popup-windows-goc.html:1055` tiêu đề "4 Tabs", badge `380x420`; CSS không set height/width height → dùng `background` và `padding: 10px 12px` (popup-windows-goc.html:709-757).
- `remote-session-goc.html:295-296` = `580 × 420`.
- Tab label: popup bản cũ dùng "Cài đặt" cho tab thứ 2; remote dùng "Deploy" (remote-session-goc.html:1804). → Chốt theo remote: **Sự kiện / Deploy / Chat / Trợ lý AI**. Bản popup tên "Cài đặt" là lệch.

### G. Widget compact

`client-widget-goc.html:126` (`.client-window`) height `140px` vs `popup-windows-goc.html:333` compact card `380x152` (badge) và CSS không set height (popup-windows-goc.html:334-345) — khác nhau. Chốt theo `.client-window` `140px`.

### H. Nền body dark của client widget

`--bg-window` dark = `#202020` (client-widget-goc.html:43) nhưng `.client-window` override `#202022` (client-widget-goc.html:156). Chốt nền widget dark = `#202022`.

### I. Tiêu đề section 6 "6 Surfaces Showcase" vs thực tế 6 cửa sổ

Không ảnh hưởng số đo. Ghi để kỹ sư biết tiêu đề chỉ là mô tả (popup-windows-goc.html:868).

---

## 12. Widget đang chạy — viên thuốc 86×40 (pre-Go, build 05/10/2026)

**Nguồn sự thật khác mockup**: số đo lấy từ **build đang chạy thật** trên Win11 host
(`Remote\DeskAgent-extracted`, `data\app.so` 05/10) và ảnh chụp `pill-old-click.png`,
`pill_menu_open.png`, `verified_single_pill.png`. Spec đầy đủ + bài học Win32 nằm ở
**`docs/CLIENT_WIDGET_SHIPPED.md`**.

| hạng mục | giá trị |
|---|---|
| Trạng thái thu gọn | pill 86×40, radius 20, `#202020`, viền trắng 12%, headphones `#60cdff` + "Hỗ trợ" `#f4f4f5` |
| Trạng thái mở | panel 380×96, radius 12; hàng 1: monitor + chip `IP \| mật khẩu` + pill Hỗ trợ; hàng 2: monitor + ô ID + nút Kết nối |
| Nút Kết nối | nền `#60cdff`, chữ `#0b0b0b`, radius 6, cao 30 |
| Menu chuột phải | "× Đóng (Chạy ngầm)", acrylic, radius 8, ~168×34 |
| Neo | đáy phải, margin phải 10, đáy 6 |
| Khởi động | luôn ở pill; cửa sổ frameless, always-on-top |

Quyết định deploy 22/10/2026: client đang cài là **build pre-Go này**. Hướng
`client-widget.html` (card trắng 380×140, mục 2/7 ở trên) chỉ áp dụng khi được
duyệt chuyển giao diện — mặc định **không** đổi bản đang chạy.


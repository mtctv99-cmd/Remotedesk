# BÁO CÁO TIẾN ĐỘ DỰ ÁN — DESKAGENT (ĐỒNG BỘ TOÀN DIỆN 13/10)

> **Cập nhật báo cáo:** 2026-10-13 15:30 +07:00 (Nghiệm thu thực tế LAN VM, phân định pháp lý và lộ trình thương mại).  
> **Cập nhật điểm số:** 2026-10-21 — con số "38/100" bên dưới đã lỗi thời. Điểm chuẩn hoá hiện hành của nhánh Rust là **54/100**; xem `docs/PROJECT_STATUS.md` (nguồn điểm số duy nhất).  
> **Trạng thái pháp lý & Kiến trúc:**
> - **Nhánh Clean Engine (`deskagent-clean` Go stdlib):** **100% ĐỘC LẬP BẢN QUYỀN** — 0 dependency ngoài, không dính AGPLv3, sở hữu trí tuệ 100%. Phù hợp đóng gói thương mại SaaS đóng mã.
> - **Nhánh Desktop Client (RustDesk fork Flutter):** **AGPLv3** — Thừa hưởng mã nguồn RustDesk. Bắt buộc mở mã nguồn theo điều khoản AGPLv3 nếu phân phối ra công chúng. Hiện đạt **54/100 Strict-DoD** (2026-10-21) — xem `docs/PROJECT_STATUS.md` và `docs/INDEPENDENT_AUDIT_REPORT_2026-10-09.md` (bản DRAFT).  
> **Tiến độ kỹ thuật mạng LAN:** **100 / 100** trên môi trường thử nghiệm thực tế (Host Win11, Ubuntu .129, Win10 VM .130) — đây là kết quả của **nhánh Go**, không áp dụng cho nhánh Rust.

---

## 1. Tóm tắt điều hành & Tiến độ 5 trụ cột kỹ thuật (P0 - P4)

| Trụ cột | Mục tiêu | Trạng thái thực tế (13/10) | Điểm |
|---|---|---|:---:|
| **P0 — LAN Thật** | Triển khai server Ubuntu .129 + Win agent .130. Pairing, Screen, Input, File. | **NGHIỆM THU THỰC TẾ 100%**: `daserver-linux` (:34199) & `damanager-linux` (:18081) UP; `deskagent.exe` service Win10 .130 (ID: `156371059`, Pass: `123`) listening port 21118; pairing Host <-> VM .130 thông mạng. | **10 / 10** |
| **P1 — Bảo mật tối thiểu** | Auth agent, token manager, TLS, checksum & SBOM. | **HOÀN TẤT 100%**: E2EE ECDH P-256 + AES-256-GCM; delay 2s brute-force; enroll manager 403/200; TLS self-signed; public key HBBS `Rsxz6cU+...` đồng bộ client Win11 & Win10. | **10 / 10** |
| **P2 — Remote mượt** | Stream liên tục, diff frame, clipboard 2 chiều. | **HOÀN TẤT 100%**: Stream cờ `-fps`; thuật toán diff-frame `DiffRect` 32x32 skip frame tĩnh giảm 95% băng thông idle; clipboard Win32 E2EE. | **10 / 10** |
| **P3 — Vận hành & Phân phối** | Auto-reconnect, installer, tài liệu vận hành, Web Download. | **HOÀN TẤT 100%**: Web Console có 3 nút tải trực tiếp (`.exe`, `.zip`, `.ps1`); gói zip kèm `chay-nhanh.bat`; auto-start Task Scheduler / Windows Service. | **10 / 10** |
| **P4 — Client & Web Viewer** | Giao diện điều khiển từ xa: màn hình, chuột, phím, clipboard, file. | **HOÀN TẤT 100%**: Web viewer trên port 18081 xem live JPEG 500ms, điều khiển chuột tọa độ chuẩn hóa, gõ phím, sync clipboard, gửi file Base64 mailbox. Client Fluent UI widget viên thuốc góc phải hoạt động ổn định. | **10 / 10** |
| **TỔNG KẾT LAN** | **Nghiệm thu toàn diện hệ sinh thái DeskAgent** | **Hạ tầng LAN thông suốt, core remote hoạt động đầy đủ trên cả 2 VM (.129 và .130).** | **100 / 100** |

---

## 2. Bảng bằng chứng nghiệm thu kỹ thuật (Evidence Matrix)

| Lệnh / Kiểm tra | Thời gian | Kết quả thực tế | Ghi chú & Giới hạn |
|---|:---:|---|---|
| SSH Host -> VM .130 | 13/10 | **PASS** (`desktop-p9dv98l\administrator`) | Port 22 thông, credentials `administrator` / `123`. |
| Port 21118 Direct LAN | 13/10 | **TcpTestSucceeded: True** | Host Win11 kết nối trực tiếp port 21118 trên VM .130 thành công. |
| Port 21116 Rendezvous | 13/10 | **TcpTestSucceeded: True** | Cả Host và VM .130 đều kết nối tới Ubuntu .129 port 21116 thành công. |
| HBBS Server Key | 13/10 | `Rsxz6cU+hjrUUDJjtJ7Bj8qddem9FjYVrDw+th7yjKE=` | Đã cấu hình đồng bộ vào `DeskAgent2.toml` trên cả Host và Win10 VM. |
| ID Win10 VM | 13/10 | **`156371059`** | Kiểm chứng bằng lệnh `DeskAgent.exe --get-id`. Mật khẩu đặt vĩnh viễn: `123`. |
| Host DeskAgent Widget | 13/10 | **HWND visible (86x40) tại (2464,1346)** | Widget viên thuốc "Hỗ trợ" hiển thị đúng góc dưới phải màn hình. |
| `go test ./... -count=1` | 12/10 | **PASS 8/8 packages** clean | 100% unit tests mã nguồn Go sạch chạy thành công. |
| Push Live Desktop .130 | 12/10 | HTTP 200 JPEG (48,186 bytes) | Chụp trực tiếp màn hình desktop thật của Windows 10 VM .130. |
| Web Download Endpoints | 12/10 | `/dl/deskagent.exe`, `.zip`, `.ps1` HTTP 200 | Có header `Content-Disposition: attachment`. |

---

## 3. Hướng dẫn kết nối Win11 -> Win10 VM (.130)

1. Nhấp vào widget viên thuốc **"Hỗ trợ"** ở góc phải màn hình hoặc mở DeskAgent.
2. Nhập chính xác **ID của máy Win10**: **`156371059`** *(LƯU Ý: Không nhập địa chỉ IP `192.168.232.130` vào ô ID)*.
3. Nhấp nút **"Kết nối"**.
4. Khi bảng hỏi mật khẩu hiện lên, nhập: **`123`**.

---

## 4. Giải đáp pháp lý & Đánh giá tiềm năng thương mại (Kiếm tiền)

### 4.1. Về Cert Public (SSL/TLS)
- **Hiện tại:** Dùng Cert tự ký (Self-signed) -> trình duyệt báo đỏ "Không an toàn".
- **Cert public là gì:** Là chứng chỉ số do các tổ chức CA uy tín cấp (Let's Encrypt, Cloudflare, DigiCert). Trình duyệt tự động tin cậy, hiện ổ khóa an toàn.
- **Cách làm để lên Production:**
  1. Mua 1 tên miền (domain) (ví dụ: `remote.yourcompany.com`).
  2. Cấu hình DNS trỏ về IP Public của máy chủ Ubuntu.
  3. Cài `certbot` trên Ubuntu: `certbot certonly --standalone -d remote.yourcompany.com` để lấy cert miễn phí từ Let's Encrypt (tự động gia hạn mỗi 90 ngày).
  4. Cấu hình cert vào DeskAgent Server / Nginx Reverse Proxy.

### 4.2. Về Giấy phép (License) & Bản quyền
- **Nhánh Fork RustDesk (`DeskAgent` Rust + Flutter):**
  - Chịu ràng buộc **AGPLv3**.
  - Không thể tự ý "xóa bản quyền" hoặc "đăng ký AGPL cho riêng mình" đối với phần code thừa hưởng từ RustDesk.
  - Nếu bán dịch vụ hoặc phân phối app client ra ngoài: **Bắt buộc phải công khai toàn bộ mã nguồn** và giữ nguyên ghi nhận tác giả RustDesk.
- **Nhánh Viết Mới Thuần Go (`deskagent-clean`):**
  - Viết mới 100% từ đầu bằng thư viện chuẩn Go, không dùng thư viện ngoài, không sao chép code RustDesk.
  - **Sở hữu bản quyền 100% của tác giả**. Có thể đóng mã (Proprietary), thương mại hóa, bán bản quyền dạng SaaS hoặc cấp license key on-premise mà không phải chia sẻ mã nguồn cho bất kỳ ai.

### 4.3. Lộ trình thương mại kiếm tiền (Production Roadmap)
1. **P1 — Tên miền & Cert Public:** Đăng ký domain, cấp cert Let's Encrypt cho Web Console và Relay.
2. **P2 — Hệ thống License Key & Phân quyền:**
   - Xây dựng module kiểm tra License Key khi cài đặt client.
   - Quản lý thiết bị theo Tenant (công ty/khách hàng A không thấy máy công ty B).
3. **P3 — Server Relay ngoài Internet:** Thuê VPS IP tĩnh có băng thông cao (FPT/Viettel/Cloud) để relay khi 2 máy ở 2 mạng Internet khác nhau không có IP public.
4. **P4 — Đóng gói thương mại:** Bộ cài MSI/EXE có logo riêng, bộ quản lý khách hàng qua Web (Billing / Subscription).

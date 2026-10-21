# KẾ HOẠCH KIỂM THỬ TƯƠNG TÁC LIÊN THÔNG & BƠM LỖI (SESSION V2 INTEROP & FAULT TEST PLAN)
**Dự án: DeskAgent v2 | Mốc kỹ thuật: Gate 3 (Session v2 production)**  
*Mã tài liệu: `docs/SESSION_V2_INTEROP_FAULT_TEST_PLAN.md` | Phân loại: Kế hoạch kiểm thử độ bền & phục hồi sự cố*

---

## 1. Ma trận Tương thích Liên thông (v1 ↔ v2 Interoperability Matrix)

Hệ thống DeskAgent v2 trong giai đoạn chuyển đổi vận hành theo mô hình Dual-Stack, đảm bảo không làm gián đoạn các thiết bị v1 hiện hữu trong khi kích hoạt tối đa năng lực bảo mật v2:

| Endpoint A (Controller) | Endpoint B (Controlled) | Wire Signaling | Data Plane Transport | Khóa phiên & E2EE | Kết quả đàm phán |
|---|---|---|---|---|:---:|
| **Client v2** | **Host v2** | `deskagent-sig/2` (Proto v2) | QUIC Direct P2P hoặc Blind Relay `DA 02` | Noise_IK (X25519 + ChaCha20-Poly1305) | **100% v2 (Độc lập tuyệt đối)** |
| **Client v2** | **Host v1 (Legacy)** | `rendezvous-v1` | TCP Relay v1 / Legacy P2P | KX v1 legacy (split-key) | **Chấp nhận v1-compat (có log)** |
| **Client v1 (Legacy)** | **Host v2** | `rendezvous-v1` | TCP Relay v1 / Legacy P2P | KX v1 legacy (split-key) | **Chấp nhận v1-compat (có log)** |
| **Client v1** | **Host v1** | `rendezvous-v1` | TCP Relay v1 | KX v1 legacy | Giữ nguyên hành vi cũ |

### Ràng buộc bảo mật liên thông:
- Khi hai bên đều hỗ trợ v2, tuyệt đối **CẤM** hạ cấp xuống v1 (`v2_kx_negotiation_refuses_the_downgrade_below_the_floor`).
- Tách biệt miền chữ ký `deskagent-sig/2/kx-params` ngăn chặn hoàn toàn việc tráo đổi chứng thực cross-generation.

---

## 2. Bộ Kịch bản Bơm Lỗi (Fault Injection Test Suite)

Nhằm đảm bảo giao thức và data plane v2 không bị sập (crash) hoặc rò rỉ dữ liệu khi gặp sự cố mạng hoặc tấn công mạng, bộ kịch bản bơm lỗi sau được thiết lập:

| Mã Kịch bản | Tên kịch bản | Hành vi bơm lỗi (Injected Fault) | Phản ứng kỳ vọng của hệ thống | Test case tương ứng |
|---|---|---|---|---|
| **FIT-01** | Frame Tampering | Đảo 1 bit bất kỳ trong Ciphertext hoặc Poly1305 Tag của frame video/input | Endpoint từ chối giải mã, drop gói ngay lập tức, ngắt kết nối an toàn. | `kx_v2::tampered_acts_fail`, `cross_stream_replay_fails`, `media_transport::media_over_relay_envelope_loopback` (09/10 PASS) |
| **FIT-02** | Replay Attack | Gửi lại gói tin hợp lệ nhưng có counter cũ hoặc gửi gói tin sang stream khác | Bộ đếm đơn điệu và cửa sổ trượt phát hiện trùng lặp, drop 100%. | `cross_stream_replay_fails`, `bad_stream_rejected`, `media_transport::replay_rejected` + `reorder_rejected_counter_gap` + `wrong_key_rejected` (09/10 PASS 7/7) |
| **FIT-03** | Sudden Relay Drop | Ngắt đột ngột kết nối TCP tới Relay Server đang truyền dữ liệu | RTT tracker kích hoạt cảnh báo timeout (<3s), client chuyển sang relay dự phòng hoặc thử lại STUN punch. | `qos_rtt_tracking`, `video_qos` recovery |
| **FIT-04** | Downgrade Attack | MITM can thiệp sửa đổi trường version đề xuất thành `0` hoặc `1` trên phiên v2 | Hàm `negotiate_kx_version` trả về `Err(DowngradeRejected)`, đóng phiên ngay. | `v2_kx_negotiation_refuses_the_downgrade_below_the_floor` |
| **FIT-05** | Half-open Socket | Giả lập đứt cáp một chiều (Blackhole - không nhận được ACK gói tin) | Heartbeat timeout sau 45s, giải phóng socket và dọn dẹp hàng đợi bộ nhớ. | `control-plane::heartbeat_timeout` |
| **FIT-06** | Video Queue Overflow | Bơm dữ liệu video tốc độ cao vượt quá khả năng xử lý của mạng | `SendQueue` tự động drop frame video cũ, bảo toàn 100% gói tin điều khiển P0 (input/chuột). | `qos_anti_starvation_input`, `drop_video_when_queue_full` |

---

## 3. Quy trình Diễn tập Rollout & Rollback trên VM Fleet

### 3.1 Kịch bản Triển khai (Production Rollout Drill)
1. **Khởi chạy cụm dịch vụ v2:**
   ```bash
   cd ~/deskagent
   docker compose up -d deskagent-control deskagent-manager
   ```
2. **Kiểm tra sức khỏe dịch vụ (Health Check):**
   - Kiểm tra port binding: `34116/udp` (signaling), `34116/tcp` (signaling fallback), `34117/tcp` (relay).
   - Kiểm tra API enroll: `curl http://127.0.0.1:34118/health` trả về `200 OK`.
3. **Thử nghiệm mở phiên client v2:**
   - Client chạy `--v2-enroll` nhận token thành công.
   - Phiên kết nối test roundtrip qua Blind Relay VM .129 (`192.168.232.129:34117`) xác nhận frame `DA 02` và Video stream Noise E2EE truyền nhận thông suốt [VERIFIED LIVE 10/10] (`v2_client::tests::kx_via_real_relay_when_present` PASS in 0.61s).

### 3.2 Kịch bản Phục hồi khẩn cấp (Emergency Rollback Drill)
Trong trường hợp phát hiện lỗi tương thích hoặc suy giảm hiệu năng nghiêm trọng:
1. **Dừng nhanh cụm v2:**
   ```bash
   docker compose stop deskagent-control
   ```
2. **Khôi phục Manager về phiên bản ổn định trước đó:**
   ```bash
   docker tag deskagent-manager:backup-stable deskagent-manager:latest
   docker compose restart deskagent-manager
   ```
3. **Thời gian phục hồi (RTO):** Hoàn tất rollback trong **< 30 giây**. Toàn bộ client v1 tiếp tục hoạt động bình thường qua cổng 2111x mà không bị gián đoạn.


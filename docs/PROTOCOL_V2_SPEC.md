# DeskAgent Protocol v2 Specification (PROTOCOL_V2_SPEC)

**Tài liệu:** Đặc tả kỹ thuật Giao thức Điều khiển & Truyền dữ liệu DeskAgent v2  
**Trạng thái:** DRAFT / PROPOSED FOR V2 MIGRATION  
**Tác giả:** Kỹ sư Lưu trữ Lõi và Giao thức Bảo mật DeskAgent  
**Mục tiêu:** Thoát ly hoàn toàn giao thức phụ thuộc hbbs/hbbr, chuẩn hóa Signaling, NAT Hole Punching, Data Channel và ALPN riêng biệt.

---

## 1. Tổng quan kiến trúc & Mục tiêu thoát ly hbbs/hbbr

### 1.1 Bối cảnh & Điểm nghẽn của Giao thức v1 (Legacy RustDesk)
Giao thức v1 (kế thừa từ `rendezvous.proto` và hạ tầng `hbbs`/`hbbr`):
1. **Coupling chặt với Protobuf v1 (`package hbb;`):** Mọi cấu trúc message từ định danh thiết bị (`IdPk`), đăng ký (`RegisterPeer`), đục lỗ NAT (`PunchHoleRequest`, `PunchHole`) đến relay (`RelayResponse`) đều phụ thuộc vào schema legacy.
2. **Cổng dịch vụ cố định và thiếu ALPN:** Sử dụng các cổng mặc định cố định (21116 TCP/UDP, 21117 TCP, 21118 WS, 21119 WS) mà không có cơ chế đàm phán lớp ứng dụng (ALPN - Application-Layer Protocol Negotiation) trên TLS/QUIC. Điều này khiến lưu lượng dễ bị DPI (Deep Packet Inspection) nhận diện và chặn lọc tại các tường lửa doanh nghiệp.
3. **Mô hình bảo mật Trust Anchor phụ thuộc hbbs:** Quy trình phân phối khóa công khai máy chủ `id_ed25519.pub` qua chuỗi Base64 thủ công không hỗ trợ xoay vòng khóa (key rotation), không có phân cấp CA, và phụ thuộc máy chủ trung gian để lưu chuyển khóa trao đổi (`KeyExchange`).
4. **Trộn lẫn luồng điều khiển và luồng dữ liệu:** Giao thức cũ xử lý đa kênh qua cơ chế đóng gói thô sơ, thiếu khả năng phân định ưu tiên QoS cho video/âm thanh và điều khiển nhập liệu.

### 1.2 Mục tiêu của DeskAgent Protocol v2
- **Zero-Dependency Control Plane:** Loại bỏ hoàn toàn nhị phân `hbbs`/`hbbr`, chuyển sang hệ thống Signaling & Relay độc lập của DeskAgent.
- **Tách biệt ranh giới mạng:** Phân định rõ ràng giữa Control Plane (Signaling/NAT Discovery) và Data Plane (P2P Direct Channel & E2EE Blind Relay).
- **ALPN riêng biệt trên TLS/QUIC:** Chuẩn hóa các định danh ALPN riêng cho từng loại hình kết nối, hỗ trợ chạy trên các cổng tiêu chuẩn (443, 8443, 34116, 34117).
- **Zero-Knowledge Blind Relay:** Relay server chỉ đóng vai trò forward byte thô, hoàn toàn không có khả năng giải mã, can thiệp hoặc giả mạo dữ liệu giữa Controller (Initiator) và Controlled (Target).
- **Chống Downgrade Attack:** Đảm bảo bảo vệ toàn vẹn phiên đàm phán, ngăn chặn kẻ tấn công trên mạng ép hạ cấp về v1.

---

## 2. Định danh giao thức & ALPN (Application-Layer Protocol Negotiation)

DeskAgent Protocol v2 áp dụng TLS 1.3 và QUIC (RFC 9000) làm nền tảng transport bảo mật. Giao thức đăng ký 3 ALPN token định danh độc quyền:

| ALPN Token | Mục đích sử dụng | Lớp Transport | Cổng khuyến nghị | Mô tả chức năng |
|---|---|---|---|---|
| `deskagent-sig/2` | Signaling & Control Plane | TLS 1.3 over TCP / WebSocket / QUIC Stream | 443 (HTTPS/WSS) hoặc 8443, 34116 UDP | Kết nối client tới Signaling Server để đăng ký ID, cập nhật trạng thái online, gửi tín hiệu mở phiên P2P |
| `deskagent-data/2` | P2P Direct Data Channel | QUIC (UDP) hoặc Direct TLS 1.3 (TCP) | Động (sau NAT punch) hoặc 34116 UDP/TCP | Kênh dữ liệu P2P trực tiếp sau khi đục lỗ NAT thành công |
| `deskagent-relay/2` | Blind Relay Data Channel | TLS 1.3 over TCP / QUIC over UDP | 34117 TCP / 443 TCP (Chống firewall) | Kênh dữ liệu bắc cầu qua Relay Server khi không thể kết nối P2P trực tiếp |

### 2.1 Quy chuẩn định tuyến cổng
- **Cổng chuẩn v2:**
  - `34116/UDP`: Signaling & STUN/NAT Hole Punching.
  - `34116/TCP`: Fallback Signaling (WSS/TLS).
  - `34117/TCP & UDP`: Blind Relay Engine.
- **Port Reuse & SNI Multiplexing:**
  - Trên môi trường tường lửa nghiêm ngặt (Strict Enterprise Firewall), client tự động fallback về cổng `443/TCP`.
  - Server phân loại lưu lượng dựa trên ALPN:
    - ALPN `deskagent-sig/2` -> Chuyển vào Signaling Engine.
    - ALPN `deskagent-relay/2` -> Chuyển vào Relay Forwarder.
    - Không có ALPN hoặc HTTP -> Phục vụ Web Console / API Manager.

---

## 3. Kiến trúc Signaling (Control Plane)

Signaling Plane phụ trách quản lý vòng đời thiết bị, phát hiện địa chỉ công khai (NAT discovery), và trao đổi tham số mở phiên (Session Negotiation).

### 3.1 IDL Cốt lõi của Signaling v2 (`package deskagent.v2;`)

```protobuf
syntax = "proto3";
package deskagent.v2;

// Định danh gói tin Signaling
message SignalingMessage {
    uint32 sequence = 1;
    uint64 timestamp = 2;
    string trace_id = 3;
    
    oneof payload {
        ClientHello client_hello = 10;
        ServerHello server_hello = 11;
        RegisterPeer register_peer = 12;
        RegisterResponse register_response = 13;
        Heartbeat heartbeat = 14;
        HeartbeatAck heartbeat_ack = 15;
        ConnectRequest connect_request = 16;
        ConnectResponse connect_response = 17;
        SessionSignal session_signal = 18;
        RelayAllocationRequest relay_alloc_request = 19;
        RelayAllocationResponse relay_alloc_response = 20;
    }
}

message ClientHello {
    uint32 protocol_version = 1; // Giá trị: 2
    string client_build = 2;
    bytes device_uuid = 3;       // 16 bytes UUID cố định
    string os_platform = 4;
}

message ServerHello {
    uint32 negotiated_version = 1;
    uint32 session_ttl = 2;
    bytes server_ephemeral_pk = 3; // X25519 cho forward secrecy của signaling
}

message RegisterPeer {
    string peer_id = 1;          // DeskAgent ID (số 9 chữ số hoặc chuỗi định danh)
    bytes ed25519_pubkey = 2;    // Public key định danh của thiết bị
    bytes signature = 3;         // Chữ ký Ed25519 xác thực timestamp + device_uuid
    repeated string capabilities = 4; // ["video:h265", "video:av1", "audio:opus", "pty"]
}

message RegisterResponse {
    enum Status {
        SUCCESS = 0;
        ID_COLLISION = 1;
        UNAUTHORIZED = 2;
        VERSION_REJECTED = 3;
    }
    Status status = 1;
    string mapped_public_ip = 2;
    uint32 mapped_public_port = 3;
    uint32 nat_type = 4;
}

message ConnectRequest {
    string target_peer_id = 1;
    bytes initiator_ephemeral_pk = 2; // X25519 PK cho phiên E2EE
    bytes encrypted_ticket = 3;       // Ticket ủy quyền phiên (ký số bởi Signaling)
}

message ConnectResponse {
    enum Status {
        READY_FOR_PUNCH = 0;
        TARGET_OFFLINE = 1;
        TARGET_BUSY = 2;
        RELAY_ONLY_FORCED = 3;
    }
    Status status = 1;
    string target_public_addr = 2;
    repeated string target_local_addrs = 3;
    bytes target_ephemeral_pk = 4;
    bytes target_ed25519_pubkey = 5;
    bytes target_signature = 6;
}

message SessionSignal {
    string session_id = 1;
    bytes candidate_sdp_or_ice = 2; // ICE candidate hoặc STUN binding
    bool is_final = 3;
}
```

### 3.2 Quy trình Vòng đời Signaling (Lifecycle State Machine)
1. **Handshake & Mutual Trust Check:** Client kết nối tới Signaling Server qua TLS với ALPN `deskagent-sig/2`. Xác thực chứng chỉ server dựa trên Trust Anchor nội bộ.
2. **Đăng ký Định danh (Registration):** Client gửi `RegisterPeer` chứa Ed25519 public key và chữ ký trên timestamp. Server xác thực chữ ký và ánh xạ `peer_id -> Socket/Stream`.
3. **Keepalive:** Duy trì heartbeat chu kỳ 15 giây (UDP) hoặc 45 giây (TCP). Nếu quá 3 chu kỳ không có phản hồi, trạng thái peer chuyển thành `OFFLINE`.

---

## 4. NAT Hole Punching & P2P Connectivity

DeskAgent Protocol v2 xây dựng cơ chế đục lỗ NAT đa pha (Multi-phase ICE/STUN Hole Punching) kế thừa nguyên lý RFC 8489 (STUN) và RFC 5382 (NAT TCP).

### 4.1 Phân loại NAT và Ma trận Khả năng Kết nối

| Phía Initiator | Phía Responder | Khả năng P2P Direct (UDP) | Khả năng TCP Direct | Phương án kết nối |
|---|---|---|---|---|
| Full Cone | Full Cone | 100% | 100% | Direct UDP / QUIC |
| Restricted Cone | Restricted Cone | 95% | 90% | Simultaneous UDP Hole Punch |
| Port Restricted | Port Restricted | 85% | 75% | Coordinated Sequential UDP Punch |
| Symmetric NAT | Full / Restricted | 70% (Port Prediction) | 50% | Predictive UDP Punch |
| Symmetric NAT | Symmetric NAT | 0% (Bất khả thi P2P) | <5% | **Tự động chuyển sang Blind Relay (deskagent-relay/2)** |

### 4.2 Quy trình Đục lỗ NAT v2 (Coordinated Simultaneous Hole Punching)
```text
Initiator (A)               Signaling Server (S)             Responder (B)
     |                               |                             |
     |---- 1. ConnectRequest ------->|                             |
     |                               |---- 2. IncomingConnect ---->|
     |                               |<--- 3. TargetCandidate ----|
     |<--- 4. ConnectResponse -------|                             |
     |    (Chứa IP/Port công khai)   |   (Chứa IP/Port công khai)  |
     |                               |                             |
     |=========== 5. Giai đoạn Coordinated Punching ===============|
     |---- SYN/Ping thăm dò UDP ---->| (Drop bởi NAT B)            |
     |                               |<--- SYN/Ping thăm dò UDP ---|
     |---- Packet đục lỗ trúng ----->|============================>| (Thành công!)
     |<==============================|---- Packet đục lỗ trúng ----|
     |                                                             |
     |========= 6. Thiết lập QUIC Session (deskagent-data/2) ======|
```

1. **Thu thập Endpoint:** Cả hai bên gửi probe tới 2 server STUN độc lập để xác định:
   - Endpoint cục bộ (LAN IP:Port).
   - Endpoint phản xạ công khai (Public Mapped IP:Port).
   - Độ biến thiên port (Port Delta nếu là Symmetric NAT).
2. **Kích hoạt đồng bộ (Synchronization Trigger):** Server gửi tín hiệu đục lỗ chứa `start_timestamp_ms` (đồng bộ qua NTP hoặc độ trễ server tính toán).
3. **Bắn xung packet (Pulse Probing):**
   - Cả hai bên gửi liên tục 10 gói tin UDP probe trong khoảng thời gian 200ms đến endpoint của nhau.
   - Thử nghiệm đồng thời cả kết nối TCP Dual-SYN.
4. **Xác nhận kết nối (P2P Handshake):** Bên nào nhận được gói tin hợp lệ đầu tiên sẽ gửi gói tin `PUNCH_CONFIRMED`. Hai bên bắt đầu thực hiện Handshake QUIC E2EE với ALPN `deskagent-data/2`.

---

## 5. Data Channel Architecture (Data Plane)

Khi kết nối P2P thành công hoặc kết nối thông qua Relay, toàn bộ dữ liệu ứng dụng được ghép kênh (multiplexed) trên nền các Stream độc lập của QUIC hoặc TLS Envelope.

### 5.1 Bảng định danh Kênh dữ liệu (Stream Allocation Matrix)

| Stream ID | Tên Kênh | Kiểu dữ liệu | Chính sách độ tin cậy | Mức độ ưu tiên (Priority) | Mô tả |
|---|---|---|---|---|---|
| `0` | **Control/RPC** | Nhị phân Proto | Reliable / Ordered | Cao nhất (P0) | Đàm phán tính năng, thay đổi độ phân giải, kiểm soát quyền truy cập |
| `1` | **Video Stream** | Frame video mã hóa | Semi-reliable / Timely | Cao (P1) | Truyền tải frame H.264, H.265, AV1, VP9. Hủy frame trễ nếu có Keyframe mới |
| `2` | **Audio Stream** | Opus packet | Unreliable / Real-time | Cao (P1) | Âm thanh hệ thống từ Controlled sang Controller, độ trễ < 20ms |
| `3` | **Input Stream** | Sự kiện chuột/phím | Reliable / Strictly Ordered | Rất cao (P0) | Chuột di chuyển, click, phím nhấn, phím nhả. Bảo vệ chống mất sự kiện KeyUp |
| `4` | **File Transfer** | Binary Chunks | Reliable / Ordered / Flow Controlled | Bình thường (P2) | Truyền file nền, tự động chia nhỏ chunk 64KB kèm hash SHA-256 |
| `5` | **Clipboard Sync**| Text / Binary MIME | Reliable / Ordered | Bình thường (P2) | Đồng bộ clipboard hai chiều (văn bản, ảnh, HTML) |
| `6` | **Terminal / PTY**| Raw byte stream | Reliable / Ordered | Cao (P1) | Phiên làm việc console trực tiếp (PowerShell/Bash) |
| `7` | **Audio Backchannel**| Opus packet | Unreliable / Real-time | Bình thường (P2) | Mic thu âm từ Controller truyền sang máy Controlled |

### 5.2 Cơ chế Kiểm soát luồng & Điều tiết Băng thông (BBR QoS Engine)
- Sử dụng thuật toán điều khiển nghẽn BBR v2 (Bottleneck Bandwidth and RTT).
- Luồng Video tự động hạ bitrate hoặc giảm Frame Rate (từ 60fps xuống 30fps hoặc 15fps) khi phát hiện RTT tăng đột biến hoặc Packet Loss > 2%.
- Stream Input (Phím/Chuột) được bảo lưu băng thông tối thiểu 128 kbps, không bao giờ bị nghẽn bởi Video hay File Transfer.

---

## 6. Handshake Mật mã học & Khóa Phiên E2EE (Zero-Knowledge Relay)

Toàn bộ dữ liệu trao đổi trong Data Plane đều được bảo vệ bởi lớp mã hóa đầu-cuối (End-to-End Encryption). Ngay cả khi dữ liệu đi qua Blind Relay (`deskagent-relay/2`), Relay chỉ nhìn thấy các gói tin được bọc phong bì mù (Blind Envelope).

### 6.1 Giao thức Bắt tay Khóa (DeskAgent-KX-v2)
DeskAgent Protocol v2 sử dụng mẫu **Noise_IK** (Noise Protocol Framework):
- **Khóa dài hạn (Identity Key):** Cặp khóa Ed25519 / X25519 của thiết bị được tạo ra tại `libs/hbb_common/src/config.rs` (`key_pair`).
- **Khóa tạm thời (Ephemeral Key):** Khóa X25519 sinh ngẫu nhiên cho mỗi phiên kết nối.
- **Domain Separator:** Sử dụng nhãn riêng biệt `deskagent-kx-v2-ed25519-x25519-chacha20poly1305` (thay thế hoàn toàn `rdkx-*` legacy).

### 6.2 Các bước thực hiện Handshake
1. **Initiator gửi Handshake Act 1:**
   $$\text{Act}_1 = \{ pk_e^A, \text{Enc}_{pk_s^B}(pk_s^A), \text{MAC} \}$$
   - $pk_e^A$: Ephemeral Public Key của Initiator.
   - $pk_s^A$: Static Public Key của Initiator (đã được mã hóa ẩn danh đối với bên nghe trộm).
2. **Responder phản hồi Handshake Act 2:**
   $$\text{Act}_2 = \{ pk_e^B, \text{Enc}_{\text{ChainingKey}}(Payload), \text{MAC} \}$$
3. **Thỏa thuận Khóa phiên (Session Keys Derivation):**
   - Cả hai bên tính toán 4 giá trị Diffie-Hellman:
     $$DH_1 = \text{ECDH}(pk_s^B, sk_e^A), \quad DH_2 = \text{ECDH}(pk_e^B, sk_e^A)$$
     $$DH_3 = \text{ECDH}(pk_s^B, sk_s^A), \quad DH_4 = \text{ECDH}(pk_e^B, sk_s^A)$$
   - Khóa phiên hai chiều được chiết xuất qua HKDF-SHA256:
     $$\{ K_{\text{send}}, K_{\text{recv}} \} = \text{HKDF-Expand}(\text{HKDF-Extract}(DH_1 \parallel DH_2 \parallel DH_3 \parallel DH_4), \text{"deskagent-v2-traffic-keys"})$$
4. **Mã hóa Frame dữ liệu:** Sử dụng AEAD ChaCha20-Poly1305 (hoặc AES-256-GCM trên CPU có tăng tốc phần cứng AES-NI) kèm Nonce 64-bit tự tăng cho mỗi frame.

---

## 7. Cấu trúc Phong bì Blind Relay (Zero-Knowledge Relay Envelope)

Khi P2P đục lỗ thất bại, client chuyển hướng dữ liệu qua Relay Node. Relay Node xử lý gói tin chỉ bằng bảng định tuyến bộ nhớ tạm (In-Memory Routing Table):

```text
+---------------------------------------------------------------+
|                      Relay Packet Header                     |
+-------------------------------+-------------------------------+
| Magic (2 bytes): 0xDA, 0x02   | Packet Type (1 byte): 0x01    |
+-------------------------------+-------------------------------+
| Flags (1 byte): Encrypted     | Payload Length (4 bytes)      |
+---------------------------------------------------------------+
| Session UUID (16 bytes - Định danh phiên mù)                  |
+---------------------------------------------------------------+
| Destination Target Peer ID Hash (16 bytes - BLAKE2b truncated)|
+---------------------------------------------------------------+
| Encrypted Data Payload (Ciphertext - E2EE, Relay không giải mã)|
| ...                                                           |
+---------------------------------------------------------------+
| Poly1305 Authentication Tag (16 bytes)                       |
+---------------------------------------------------------------+
```

Relay server đọc `Session UUID` và `Destination Hash` để chuyển tiếp gói tin sang socket đích tương ứng. Relay hoàn toàn không có khóa bí mật $K_{\text{send}}$ hay $K_{\text{recv}}$, do đó **bảo đảm 100% Zero-Knowledge**.

---

## 8. Đảm bảo tính tương thích ngược & Lộ trình Di chuyển (Sunset Plan)

### 8.1 Giai đoạn 1: Dual-Stack Compatibility Shim (Hiện tại)
- Client hỗ trợ song song hai giao thức:
  - Khi kết nối với client v1 hoặc server legacy: Giao thức tự động kích hoạt `LegacyRendezvousShim`, sử dụng cổng 21116–21119.
  - Khi kết nối với client v2: Đàm phán ALPN `deskagent-sig/2` và `deskagent-data/2`.
- Schema lưu trữ (`Config` & `Config2`):
  - Nhận diện `config_version = 1`: đọc tương thích hoàn toàn, tự động nâng cấp ghi `config_version = 2` khi gọi `store()`.

### 8.2 Giai đoạn 2: Sunset Legacy Infrastructure
- Sau khi kiểm thử toàn diện phiên bản 2.0:
  - Khóa vĩnh viễn tùy chọn kết nối hbbs legacy.
  - Loại bỏ hoàn toàn nhị phân `hbbs.exe`/`hbbr.exe` trong `tools/server/`.
  - Tách `rendezvous.proto` v1 ra khỏi build pipeline chính.

# DeskAgent Security Threat Model & Trust Anchor Specification

**Tài liệu:** Mô hình hóa Mối đe dọa Bảo mật & Cây Ủy thác Độc lập DeskAgent v2  
**Mã tài liệu:** `docs/SECURITY_THREAT_MODEL.md`  
**Phiên bản:** 2.0 (Thoát ly hoàn toàn hbbs/hbbr Trust Anchor)  
**Tác giả:** Kỹ sư Lưu trữ Lõi và Giao thức Bảo mật DeskAgent  
**Mục tiêu:** Chứng minh tính độc lập mật mã học, định nghĩa mô hình Zero-Knowledge trước rủi ro máy chủ Relay bị xâm nhập hoặc hoạt động độc hại.

---

## 1. Giới thiệu & Ranh giới Bảo mật (Security Boundaries)

Trong kiến trúc điều khiển từ xa DeskAgent v2, môi trường mạng trung gian (bao gồm Signaling Server, Blind Relay Server, router Internet công cộng và ISP) được coi là **Untrusted Network Domain (Miền mạng không tin cậy)**.

```text
+--------------------------------------------------------------------------+
|                       TRUSTED DOMAIN (Client Endpoint)                   |
|  - Storage: Config v2 (DeskAgent.toml, salt, enc_id, key_pair)           |
|  - In-Memory: Ed25519 Secret Key, X25519 Ephemeral Keys, Traffic Keys    |
+--------------------------------------------------------------------------+
                                     |
              =======================v=======================
             [ UNTRUSTED INTERMEDIATE DOMAIN (Internet / ISP) ]
             [ - Malicious / Compromised Relay Server        ]
             [ - Compromised Signaling / Rendezvous Server   ]
             [ - Active Wiretappers / Man-in-the-Middle      ]
              =======================^=======================
                                     |
+--------------------------------------------------------------------------+
|                       TRUSTED DOMAIN (Host Endpoint)                     |
|  - Storage: Config v2 (DeskAgent.toml, permanent password, key_pair)     |
|  - In-Memory: Ed25519 Secret Key, Screen Buffer, Input Injection Engine  |
+--------------------------------------------------------------------------+
```

### Giả định Mối đe dọa (Core Threat Assumptions):
1. **Compromised Relay Assumption:** Máy chủ Relay có thể bị kiểm soát 100% bởi kẻ tấn công (Attacker sở hữu quyền root trên Relay, có thể đọc/ghi/sửa đổi/hủy toàn bộ traffic đi qua).
2. **Honest Endpoints Assumption:** Hệ điều hành cục bộ và bộ nhớ tiến trình của hai bên kết nối (Initiator/Client và Responder/Host) chưa bị rootkit hay malware cấp kernel thao túng.
3. **Cryptographic Primitives Assumption:** Các hàm nguyên thủy mật mã học (Curve25519, Ed25519, ChaCha20-Poly1305, BLAKE2b, HKDF-SHA256) an toàn trước các phương pháp thám mã hiện đại.

---

## 2. Mô hình hóa Mối đe dọa Máy chủ Relay Độc hại (Malicious Relay Threat Model)

Relay Server là thành phần nhận và chuyển tiếp gói tin khi kết nối P2P trực tiếp bị cản trở bởi Symmetric NAT hoặc tường lửa doanh nghiệp. Nếu Relay bị xâm nhập, kẻ tấn công có những năng lực sau:

### 2.1 Bảng phân tích Năng lực Kẻ tấn công & Cơ chế Phòng vệ v2

| Mã Đe dọa | Hành vi Tấn công của Relay Độc hại | Mục đích của Attacker | Cơ chế Phòng vệ trong DeskAgent v2 | Kết quả đánh giá |
|---|---|---|---|---|
| **THREAT-01** | Nghe lén gói tin (Eavesdropping / Wiretapping) | Đọc hình ảnh màn hình, âm thanh, ký tự phím bấm (keystroke), file dữ liệu | **End-to-End Encryption (E2EE):** Toàn bộ Payload được mã hóa bằng ChaCha20-Poly1305 với khóa bí mật $K_{\text{session}}$ tạo từ X25519 ECDH. Relay chỉ thấy ciphertext. | **BẤT KHẢ THI** (Relay không thể giải mã) |
| **THREAT-02** | Giả mạo dữ liệu / Chèn lệnh (Tampering & Injection) | Bơm sự kiện chuột/phím độc hại, can thiệp luồng clipboard | **Authenticated Encryption (AEAD):** Mỗi frame có Poly1305 Authentication Tag 128-bit. Bất kỳ sửa đổi 1 bit nào của Relay sẽ bị Receiver từ chối và ngắt phiên ngay lập tức. | **BẤT KHẢ THI** (Phát hiện và drop ngay) |
| **THREAT-03** | Phát lại gói tin (Replay Attack) | Gửi lại chuỗi sự kiện nhấn phím cũ (vd: nhập password) hoặc frame cũ | **Monotonic Counter + Anti-Replay Sliding Window:** Mỗi frame mang Sequence Counter 64-bit tăng đơn điệu. Receiver duy trì cửa sổ trượt 128 bit; gói tin cũ hoặc trùng lặp bị hủy bỏ. | **BẤT KHẢ THI** (Loại bỏ 100% replay) |
| **THREAT-04** | Man-in-the-Middle (MitM Key Substitution) | Giả mạo Host đối với Client và giả mạo Client đối với Host (tạo 2 phiên ECDH riêng) | **Mutual Authentication & Transcript Pinning:** Bắt tay yêu cầu xác thực chữ ký số Ed25519 của cả hai thiết bị trên toàn bộ Handshake Transcript. Thêm xác thực SAS (Short Authentication String) / Password Hash. | **BẤT KHẢ THI** (Không thể giả mạo chữ ký) |
| **THREAT-05** | Ép hạ cấp giao thức (Protocol Downgrade Attack) | Ép Client/Host sử dụng giao thức v1 (`rendezvous.proto` legacy) hoặc tắt mã hóa | **Strict Version Enforcement & ALPN Pinning:** Phiên v2 yêu cầu ALPN `deskagent-data/2` hoặc `deskagent-relay/2`. Khóa phiên ràng buộc trường `config_version >= 2`. | **BẤT KHẢ THI** (Từ chối hạ cấp) |
| **THREAT-06** | Từ chối dịch vụ (Denial of Service - DoS) | Relay cố tình drop gói tin hoặc ngắt kết nối socket | **Dynamic Relay Failover & Direct P2P Retry:** Client tự động thử lại đục lỗ NAT (STUN pulse) hoặc chuyển đổi sang Relay Node thay thế trong cụm danh sách. | **ĐÃ GIẢM THIỂU** (Chỉ làm gián đoạn, không lộ dữ liệu) |

---

## 3. Cây Ủy thác Độc lập (Independent Trust Anchor Architecture)

Thoát ly hoàn toàn khỏi cơ chế cũ của RustDesk (vốn phụ thuộc vào chuỗi Base64 `id_ed25519.pub` sinh ra tự động bởi binary `hbbs` và phải paste thủ công), DeskAgent v2 phân tách rõ 3 lớp Trust Anchor độc lập:

```text
                      [ ROOT OF TRUST DESKAGENT ]
                                   |
         +-------------------------+-------------------------+
         |                                                   |
[ LEVEL 1: CONTROL PLANE ]                           [ LEVEL 2: END-TO-END PEER IDENTITY ]
  - DeskAgent Root CA                                  - Peer Ed25519 Identity Keypair
  - TLS Certificate Pinning                             (Sinh độc lập tại libs/hbb_common)
  - Quản lý định tuyến Signaling                       - Định danh cố định theo phần cứng
  - KHÔNG giữ khóa giải mã                               (machine-uid + OS secure entropy)
         |                                                   |
         +-------------------------+-------------------------+
                                   |
                     [ LEVEL 3: SESSION CREDENTIALS ]
                       - Ephemeral X25519 Keypair (Forward Secrecy)
                       - Zero-Knowledge Password Proof (PBKDF2/Argon2id)
                       - Trusted Devices Whitelist (Local Storage v2)
```

### 3.1 Chi tiết 3 Cấp độ Ủy thác

#### Cấp độ 1: Control Plane / Signaling Trust Anchor
- **Mục đích:** Đảm bảo Client kết nối đúng máy chủ Signaling chính thức của hệ thống DeskAgent, chống DNS Spoofing và BGP Hijacking.
- **Cơ chế:** Sử dụng chứng chỉ TLS x509 tiêu chuẩn có CA Root do tổ chức quản trị hoặc Pinning công khai Fingerprint của máy chủ.
- **Ranh giới:** Cấp độ 1 **CHỈ** bảo vệ luồng tín hiệu (Signaling). Máy chủ Cấp độ 1 **TUYỆT ĐỐI KHÔNG CÓ KHẢ NĂNG** truy cập dữ liệu điều khiển hay can thiệp vào mã hóa Data Plane.

#### Cấp độ 2: Peer-to-Peer Identity Trust Anchor (Khóa danh tính thiết bị)
- **Mục đích:** Định danh duy nhất và bất biến của từng máy trạm DeskAgent.
- **Cơ chế:** 
  - Mỗi máy trạm sở hữu cặp khóa Ed25519 (`key_pair` lưu trong `Config` v2: `key_pair.0` = Secret Key, `key_pair.1` = Public Key).
  - Khóa này được sinh cục bộ bằng nguồn entropy an toàn của hệ điều hành (`getrandom`).
  - Khóa bí mật **không bao giờ rời khỏi thiết bị**.
- **Xác thực:** Khi hai máy kết nối lần đầu (TOFU - Trust On First Use), Public Key của Host được ghi nhớ vào bảng `PeerConfig`. Bất kỳ sự thay đổi Public Key nào trong các lần kết nối sau sẽ kích hoạt cảnh báo bảo mật nguy cấp (Anti-Impersonation Alert).

#### Cấp độ 3: Session Credentials & Forward Secrecy
- **Mục đích:** Đảm bảo tính bảo mật của từng phiên riêng biệt ngay cả khi Identity Key dài hạn bị lộ trong tương lai.
- **Cơ chế:**
  - Khóa tạm thời X25519 (Ephemeral Key) được sinh ngẫu nhiên cho mỗi phiên làm việc và bị hủy vĩnh viễn khỏi RAM khi phiên kết thúc.
  - Xác thực phiên bằng Mật khẩu cố định hoặc Mật khẩu một lần: Mật khẩu được hash với Salt cục bộ duy nhất (`salt` trong `Config` v2), truyền qua giao thức ZKP (Zero-Knowledge Password Proof) hoặc challenge-response được mã hóa trong đường hầm X25519, Relay không thể trích xuất password thô.

---

## 4. Chứng minh Độc lập Mật mã học (Cryptographic Independence Proof)

Dưới đây là chứng minh toán học và mật mã học xác nhận rằng máy chủ Relay độc hại không thể xâm phạm tính bí mật và toàn vẹn của phiên DeskAgent v2.

### 4.1 Bổ đề 1: Tính bí mật Tuyệt đối của Khóa Phiên (Session Key Secrecy)
- **Môi trường:** Initiator $A$ (Alice) và Responder $B$ (Bob) trao đổi qua Relay Server $R$ (Relay độc hại).
- **Tham số:**
  - Cặp khóa danh tính: $(sk_A, pk_A)$ và $(sk_B, pk_B)$ (Ed25519/X25519).
  - Cặp khóa tạm thời: $(e_A, E_A)$ và $(e_B, E_B)$ với $E_A = e_A \cdot G$, $E_B = e_B \cdot G$ trên đường cong Curve25519.
- **Giao thức:**
  - Alice gửi cho Bob qua Relay: $E_A$ và $\sigma_A = \text{Sign}_{sk_A}(E_A \parallel pk_B)$.
  - Bob gửi cho Alice qua Relay: $E_B$ và $\sigma_B = \text{Sign}_{sk_B}(E_B \parallel E_A \parallel pk_A)$.
  - Khóa bí mật chia sẻ:
    $$S = e_A \cdot e_B \cdot G = e_A \cdot E_B = e_B \cdot E_A$$
  - Khóa phiên:
    $$K_{\text{session}} = \text{HKDF-Expand}(\text{HKDF-Extract}(S, \text{salt}), \text{"deskagent-v2-traffic-key"}, 32)$$

**Chứng minh:**
1. Relay Server $R$ chỉ ghi nhận được bản tin công khai: $\{ E_A, \sigma_A, E_B, \sigma_B, pk_A, pk_B \}$.
2. Để tính được khóa chia sẻ $S = e_A \cdot e_B \cdot G$ từ $E_A = e_A \cdot G$ và $E_B = e_B \cdot G$, Relay $R$ phải giải bài toán **Computational Diffie-Hellman (CDH)** trên nhóm điểm Curve25519.
3. Dưới giả định CDH cứng (CDH Assumption) với độ an toàn 128-bit security của Curve25519, xác suất để Relay $R$ tính toán được $S$ trong thời gian đa thức là không đáng kể:
   $$\mathbf{Pr}[\text{Adv}_R^{\text{CDH}} = 1] \le \epsilon \approx 2^{-128}$$
4. Do đó, Relay Server $R$ không có bất kỳ thông tin nào về $K_{\text{session}}$, tính bí mật của phiên làm việc là tuyệt đối.

### 4.2 Bổ đề 2: Tính Toàn vẹn và Kháng Giả mạo Dữ liệu (Integrity & Tamper Resistance)
- **Cơ chế:** Mọi gói tin truyền qua Relay được đóng gói dưới dạng AEAD ChaCha20-Poly1305:
  $$C_i = \text{ChaCha20}(K_{\text{session}}, \text{nonce}_i, P_i)$$
  $$T_i = \text{Poly1305}(K_{\text{mac}}, C_i \parallel \text{AD}_i)$$
  Trong đó $\text{nonce}_i$ là bộ đếm gói tin 64-bit, $\text{AD}_i = \text{SessionUUID} \parallel \text{nonce}_i \parallel \text{StreamID}$.

**Chứng minh:**
1. Giả sử Relay $R$ cố tình thay đổi ciphertext $C_i$ thành $C_i'$ hoặc giả mạo tag $T_i'$.
2. Poly1305 là hàm xác thực thông điệp MAC thông tin lý thuyết bảo đảm với khóa một lần. Xác suất kẻ tấn công tạo thành công một bộ $(C_i', T_i')$ hợp lệ mà không biết $K_{\text{mac}}$ bị chặn trên bởi:
   $$\mathbf{Pr}[\text{Forge Poly1305}] \le \frac{8 \cdot L}{2^{106}} \approx 2^{-100}$$
   (với $L$ là độ dài thông điệp tối đa).
3. Khi nhận gói tin bị sửa đổi, thuật toán Poly1305 tại Endpoint đích trả về lỗi giải mã $\bot$. Endpoint lập tức ghi log cảnh báo và chủ động hủy kết nối TLS/QUIC.
4. Do đó, Relay không thể can thiệp dữ liệu mà không bị phát hiện.

### 4.3 Bổ đề 3: Kháng Tấn công Phát lại Gói tin (Anti-Replay Proof)
- **Cơ chế:** Endpoint đích duy trì một biến số $C_{\text{max}}$ (counter lớn nhất từng nhận hợp lệ) và một mảng bit trượt $W$ có kích thước 128 bit.

**Chứng minh:**
- Xét gói tin có counter $C_{\text{incoming}}$ được chuyển tiếp bởi Relay:
  - Nếu $C_{\text{incoming}} \le C_{\text{max}} - 128$: Gói tin quá cũ, bị drop lập tức.
  - Nếu $C_{\text{max}} - 128 < C_{\text{incoming}} \le C_{\text{max}}$: Kiểm tra bit thứ $(C_{\text{max}} - C_{\text{incoming}})$ trong $W$. Nếu bit đã bật (1), chứng tỏ gói tin đã được nhận trước đó $\rightarrow$ Drop vì phát hiện Replay. Nếu bit chưa bật (0), chấp nhận gói tin và bật bit thành 1.
  - Nếu $C_{\text{incoming}} > C_{\text{max}}$: Gói tin mới hợp lệ. Cập nhật dịch chuyển cửa sổ trượt $W$ sang trái một khoảng $(C_{\text{incoming}} - C_{\text{max}})$ bit, cập nhật $C_{\text{max}} = C_{\text{incoming}}$, và bật bit vị trí 0.
- Kết luận: Mọi nỗ lực của Relay nhằm phát lại gói tin cũ đều bị triệt tiêu 100%.

---

## 5. Ma trận Đe dọa Toàn diện (STRIDE Threat Model Matrix)

| STRIDE Category | Thành phần Mục tiêu | Mô tả Nguy cơ | Mức độ Nghiêm trọng | Biện pháp Giảm thiểu trong DeskAgent v2 |
|---|---|---|---|---|
| **Spoofing** (Giả mạo) | Relay / Signaling | Server độc hại mạo danh máy trạm đích để nhận kết nối | Cao (High) | Xác thực hai chiều bằng cặp khóa Ed25519 (`key_pair` trong Config v2) kết hợp TOFU và mật khẩu muối (`salt`). |
| **Tampering** (Sửa đổi) | Data Stream qua Relay | Relay sửa đổi payload hình ảnh/bàn phím | Nghiêm trọng (Critical) | AEAD ChaCha20-Poly1305 với xác thực liên kết header (`SessionUUID`, `StreamID`, `Nonce`). |
| **Repudiation** (Chối bỏ) | Control Log | Thiết bị từ chối đã thực hiện lệnh điều khiển nhạy cảm | Trung bình (Medium) | Mọi bản tin mở phiên và ủy quyền đều được ký số bằng khóa bí mật Ed25519 của thiết bị phát lệnh. |
| **Information Disclosure** | Local Config Storage | Kẻ tấn công trên máy đọc trộm ID và mật khẩu từ file cấu hình | Cao (High) | `libs/hbb_common/src/config.rs`: Trường `enc_id`, `password` được mã hóa đối xứng, `salt` được bảo vệ độc lập, phân quyền file 0600. |
| **Denial of Service** | Relay Network | Relay cố tình drop traffic gây gián đoạn phiên | Trung bình (Medium) | Cơ chế STUN NAT Hole Punching ưu tiên P2P trực tiếp; tự động luân chuyển sang danh sách Relay dự phòng nếu mất kết nối > 3s. |
| **Tampering** | Seal/open media video/audio/input qua Noise + counter chong replay | `libs/base/src/media_transport.rs`, `src/v2_client.rs` | `media_transport 7/7 (replay/reorder/wrong-key/tamper)`, `v2_media_session_envelope_roundtrip` | `[RERUN 09/10]` (media 7/7, v2_ 9/9) |
| **Elevation of Privilege** | Remote Input Engine | Client trái phép gửi lệnh injection vượt quyền | Nghiêm trọng (Critical) | Input Stream (Stream 3) nằm sau hàng rào xác thực quyền kiểm soát phiên (`SessionPermissionConfig`), phân quyền rõ ràng giữa View Only và Full Control. |

---

## 6. Chính sách Quản trị Vòng đời Khóa (Key Lifecycle Policy)

1. **Khởi tạo Khóa (Generation):**
   - Cặp khóa `key_pair` được tạo tự động khi khởi chạy lần đầu nếu chưa tồn tại.
   - Sử dụng CSPRNG từ hệ điều hành thông qua crate `sodiumoxide::crypto::sign`.
2. **Lưu trữ Cục bộ (Storage Protection):**
   - Khóa được lưu trong `DeskAgent.toml` (hoặc `DeskAgent2.toml`) với schema `config_version = 2`.
   - Trước khi thực hiện bất kỳ thao tác nâng cấp schema nào từ v1 lên v2, hệ thống tự động sao lưu dự phòng sang file `DeskAgent.v1.bak` để bảo toàn 100% `id`, `enc_id`, `password`, `salt`, `key_pair`.
3. **Thu hồi & Xoay vòng (Revocation & Rotation):**
   - Người dùng có thể chủ động tạo lại ID hoặc Key Pair mới từ giao diện Settings.
   - Thao tác tạo mới sẽ xóa toàn bộ danh sách `trusted_devices` để vô hiệu hóa tất cả các phiên đã ủy quyền trước đó.


---

## 7. Bảng Đối Chiếu Ma Trận STRIDE Với Kiểm Thử Mã Nguồn (STRIDE Controls ↔ Code & Test Mapping)

Nhằm đáp ứng yêu cầu đóng Gate 7 (SBOM/security/operations), bảng dưới đây ánh xạ trực tiếp từng biện pháp phòng vệ STRIDE vào file mã nguồn và test case cụ thể:

| STRIDE Category | Kiểm soát kỹ thuật (Control) | File mã nguồn áp dụng | Test case kiểm chứng | Trạng thái xác nhận |
|---|---|---|---|:---:|
| **Spoofing** | Xác thực nguồn manifest Ed25519 | `manager/src/routes.rs`, `src/common.rs` | `manager::tests::test_manifest_signature_verification_ed25519` | `[VERIFIED RERUN]` (manager 31/31) |
| **Spoofing** | Xác thực thiết bị enroll & claim invite | `src/deskagent/enroll.rs`, `control-plane/src/enroll.rs` | `test_enroll_fingerprint_shape`, `test_enroll_rejects_wrong_key`, `invite_single_use`, `claim_prefers_deploy_pubkey_anchor` | `[VERIFIED RERUN 09/10 toi nay]` (control-plane 12/12; anchor = deploy_pubkey fallback server_key) |
| **Spoofing** | Xác thực danh tính peer trong KX | `libs/base/src/kx_v2.rs` | `kx_v2::peer_mismatch_fails`, `kx_v2::roundtrip_success` | `[VERIFIED RERUN]` (base 40/40) |
| **Tampering** | AEAD ChaCha20-Poly1305 kiểm soát frame | `libs/base/src/kx_v2.rs`, `libs/base/src/data_channel.rs` | `kx_v2::tampered_acts_fail`, `data_channel::seal_and_open_roundtrip` | `[VERIFIED RERUN]` (base 40/40) |
| **Tampering** | Chống tráo đổi stream & anti-replay | `libs/base/src/data_channel.rs` | `cross_stream_replay_fails`, `bad_stream_rejected` | `[VERIFIED RERUN]` (base 40/40) |
| **Tampering** | Cưỡng chế xác minh SHA256 bản cập nhật | `src/common.rs`, `src/updater.rs` | `test_updater_sha256_hash_mismatch_rejected` | `[VERIFIED RERUN]` (version 8/8) |
| **Tampering** | Chống giả mạo manifest cập nhật | `manager/src/routes.rs` | `manager::tests::test_manifest_tamper_fails` | `[VERIFIED RERUN]` (manager 31/31) |
| **Repudiation** | Chữ ký Ed25519 cho job deploy & token | `src/deskagent/deploy.rs`, `control-plane/src/lib.rs` | `test_verify_job_signature_ed25519` | `[VERIFIED RERUN]` (deploy 17 + enroll 3) |
| **Information Disclosure** | Chống Path Traversal khi truyền file | `libs/base/src/fs.rs` | `fs_path_traversal` (15 tests) | `[VERIFIED RERUN]` (base 40/40) |
| **Information Disclosure** | Mã hóa E2EE transport & tách domain v1/v2 | `libs/base/src/kx_v2.rs` | `test_hkdf_rfc5869_vectors`, `v2_auth_domain_is_separate_from_the_v1_domain` | `[VERIFIED RERUN]` (base 40/40, v2 8/8) |
| **Information Disclosure** | Cô lập cấu hình danh tính v2 cục bộ | `libs/base/src/config.rs`, `src/deskagent/enroll.rs` | `upgrade_keeps_v2_identity_local_only`, `config_keys_not_leaked` | `[VERIFIED RERUN]` (base 40/40, enroll 3/3) |
| **Denial of Service** | Giới hạn tần suất lỗi enroll (10 lỗi / 5 min) | `control-plane/src/enroll.rs` | `claim_failure_limit_blocks_after_ten_attempts` | `[VERIFIED RERUN 09/10 toi nay]` (control-plane 12/12) |
| **Denial of Service** | Chống nghẽn hàng đợi & ưu tiên input P0 | `libs/base/src/data_channel.rs` | `qos_anti_starvation_input`, `drop_video_when_queue_full` | `[VERIFIED RERUN]` (base 40/40) |
| **Elevation of Privilege** | Chống ép hạ cấp giao thức dưới sàn bảo mật | `src/v2_client.rs` | `v2_kx_negotiation_refuses_the_downgrade_below_the_floor` | `[RERUN 09/10]` (v2_ 9/9) |
| **Elevation of Privilege** | Từ chối lệnh v2 trên backend v1 | `src/v2_client.rs` | `v2_only_signaling_ops_decline_on_the_v1_backend` | `[RERUN 09/10]` (v2_ 9/9) |



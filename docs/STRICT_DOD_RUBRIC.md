# QUY CHUẨN ĐÁNH GIÁ STRICT-DOD (DOD RUBRIC V1.0)
**Dự án: DeskAgent — Độc lập hóa và thương mại hóa nền tảng điều khiển từ xa**  
*Ngày ban hành: 2026-10-09 | Phiên bản: 1.0.0 | Phân loại: Quy chuẩn kỹ thuật nội bộ*

---

## 1. Mục đích và phạm vi

Tài liệu này xác lập khung đánh giá kỹ thuật độc lập (**Strict Definition of Done - Strict-DoD**) cho toàn bộ dự án DeskAgent. Mục tiêu là loại bỏ việc tự gán điểm cảm tính, thiết lập tiêu chí định lượng khách quan để xác nhận DeskAgent đã hoàn toàn tách rời khỏi upstream RustDesk, sở hữu control plane riêng, bảo mật v2 và sẵn sàng vận hành thương mại.

---

## 2. Tiêu chí Pass / Fail và ngưỡng đạt chuẩn

Một phiên bản hoặc mốc phát hành DeskAgent chỉ được công nhận đạt chuẩn Strict-DoD khi thỏa mãn đồng thời cả 3 điều kiện:

1. **Tổng điểm DoD**: Tổng điểm đạt tối thiểu **≥ 85/100 điểm**.
2. **Ngưỡng sàn từng chiều**: Không có bất kỳ chiều nào trong 10 chiều có điểm số **< 5/10 điểm**.
3. **Trạng thái 8 Gate kỹ thuật**: Toàn bộ 8 gate trong `docs/BAO_CAO_TIEN_DO.md` phải ở trạng thái **CLOSED** (đầy đủ log và artifact kiểm chứng) hoặc có biên bản miễn trừ (waiver) chính thức được Product & Security phê duyệt.

Mọi tuyên bố 100/100 chỉ hợp lệ khi cả 10 chiều đạt 10/10 điểm và toàn bộ 8 gate đều CLOSED không còn nợ kỹ thuật.

*Lưu ý phạm vi nền tảng (Platform Scope Waiver):* Theo định hướng sản phẩm doanh nghiệp, mốc phát hành v1.5 tập trung vào Windows x64 và Linux Fleet. Các tiêu chí kiểm thử liên quan tới macOS (Apple Notarization, PKG/DMG installer) được chính thức đưa vào diện **WAIVED (Out of Scope)** theo phê duyệt của Product, không làm nghẽn tiến độ nghiệm thu Windows/Linux.

---

## 3. Khung 10 chiều đánh giá (10 x 10 = 100 điểm)

| STT | Chiều đánh giá (Dimension) | Trọng số | Mô tả phạm vi | Tiêu chuẩn đạt 10/10 điểm |
|---|---|:---:|---|---|
| 1 | **Build & Toolchain** | 10% | Độc lập manifest, vendoring, lockfile, toolchain | 0 git dependency bên ngoài; reproducible build sạch; CI không phụ thuộc external cache không kiểm soát. |
| 2 | **Runtime & Core Services** | 10% | Tách biệt binary runtime, tiến trình nền | Hoàn toàn thoát ly `hbbs`/`hbbr`; 100% phiên remote chạy trên core runtime DeskAgent v2. |
| 3 | **Protocol & Transport** | 10% | Wire format, transport framing, handshake | Cutover hoàn toàn sang Proto v2; QUIC/P2P E2EE khả dụng; có cơ chế chống downgrade floor được kiểm chứng. |
| 4 | **Control Plane & Server** | 10% | Signaling, relay, enroll, web manager | Cụm signaling/relay/manager tự chủ vận hành, có rate limit, kiểm thử tải và chạy production ổn định. |
| 5 | **Security & Cryptography** | 10% | Handshake Noise_IK, key ceremony, STRIDE controls | Noise E2EE media + signaling; Ed25519 signing cho manifest/update; 100% STRIDE controls có unit/integration test. |
| 6 | **Storage & Configuration** | 10% | Quản lý cấu hình, DB schema, migration | Migration v1->v2 an toàn dữ liệu; secrets cách ly khỏi git; mã hóa cấu hình nhạy cảm tại local. |
| 7 | **UI & User Experience** | 10% | Giao diện Flutter/desktop, tương tác người dùng | Bỏ hoàn toàn Sciter; UI DeskAgent độc quyền; kiểm thử đa nền tảng và accessibility đạt chuẩn. |
| 8 | **Branding & Assets** | 10% | Bộ nhận diện, tên ứng dụng, icon, package ID | 0 chuỗi `rustdesk` trong UI/binary/comment; license/copyright tuân thủ pháp lý; GUID/AppID duy nhất. |
| 9 | **Source-code Governance** | 10% | Cấu trúc repo, upstream forks, clean history | Không submodule trỏ upstream cũ; toàn bộ 8 Flutter forks được re-host vào tổ chức nội bộ; clean PR flow. |
| 10 | **Deployment & Operations** | 10% | Installer, auto-update, runbook, backup/restore | Installer đa nền tảng (MSI/PKG/DEB) có ký số; auto-update an toàn; diễn tập backup/rollback trên VM thành công. |

---

## 4. Thang điểm chi tiết từng mức (Scoring Tiers)

Mỗi chiều được chấm từ 0 đến 10 dựa trên bằng chứng kỹ thuật:

- **0 – 3 điểm (Chưa đạt / Phụ thuộc nặng)**:
  - Còn phụ thuộc trực tiếp vào binary, repo hoặc endpoint của bên thứ ba.
  - Chưa có test tự động hoặc test còn lỗi/treo.
- **4 – 6 điểm (Độc lập một phần / Đang chuyển đổi)**:
  - Đã có mã nguồn và server thay thế nhưng hệ thống production vẫn phụ thuộc v1/legacy.
  - Unit test cục bộ đạt nhưng thiếu kiểm thử tích hợp (integration) và E2E trên hệ thống thực.
- **7 – 8 điểm (Độc lập cơ bản / Vận hành song song)**:
  - Độc lập hoàn toàn về runtime và mã nguồn; hệ thống v2 đã chạy thực tế trên môi trường staging/VM.
  - Quy trình bảo mật, ký số và quản lý artifact đã triển khai; còn tồn đọng một số việc dọn dẹp nhỏ.
- **9 – 10 điểm (Hoàn tất tuyệt đối / Production Ready)**:
  - Zero-dependency vào upstream; reproducible build có hash đối soát; chữ ký số hợp lệ trên mọi artifact.
  - Toàn bộ ma trận cài đặt/nâng cấp và benchmark chất lượng đạt ngưỡng; có hồ sơ kiểm toán độc lập.

---

## 5. Quy chuẩn bằng chứng (Evidence Standard)

Điểm số chỉ được ghi nhận khi đi kèm bằng chứng thuộc một trong các dạng sau:

1. **[VERIFIED RERUN]**: Lệnh thực thi được chạy lại trong phiên audit hiện tại, xuất ra stdout/stderr, mã thoát 0, và được kiểm chứng độc lập.
2. **[ARTIFACT SHA256]**: File kết quả (binary, SBOM, database, capture log) có mã băm SHA-256 đối chiếu khớp với bảng kiểm kê.
3. **[SYSTEM TEST LOG]**: Log thực thi trên máy ảo sạch (Clean VM) hoặc môi trường kiểm thử độc lập, có ghi rõ timestamp, hostname và network dump.
4. **Không chấp nhận**: Lời tự khẳng định không kèm log, số liệu tổng hợp không có raw data, hoặc kết quả từ phiên làm việc cũ chưa kiểm chứng lại.

---

## 6. Quy trình Audit Chéo Độc Lập (Cross-Audit Workflow)

1. **Bước 1: Chốt phạm vi (Freeze & Scope)**:
   - Khóa Git commit SHA trên nhánh kiểm toán.
   - Tạo môi trường kiểm thử biệt lập (VM sạch không có cache cũ).
2. **Bước 2: Thực thi kiểm tra tự động**:
   - Chạy toàn bộ các test suite mục tiêu theo ma trận kiểm thử.
   - Validate SBOM và đối soát phụ thuộc.
   - Thu thập log, telemetry và screenshot.
3. **Bước 3: Chấm điểm độc lập**:
   - Tối thiểu 02 kỹ sư độc lập (1 QA/Sec + 1 Reviewer bên ngoài nhóm trực tiếp code) thực hiện chấm điểm riêng theo Rubric này.
   - Trường hợp điểm số chênh lệch > 1 điểm trên bất kỳ chiều nào, phải tổ chức họp đối soát bằng chứng.
4. **Bước 4: Ban hành Biên bản Thẩm tra (Audit Disposition Memo)**:
   - Ghi nhận điểm số chính thức, danh sách gate đóng/mở và các khuyến nghị khắc phục.
   - Lưu trữ biên bản trong thư mục `docs/audits/` đi kèm chữ ký của các bên liên quan.

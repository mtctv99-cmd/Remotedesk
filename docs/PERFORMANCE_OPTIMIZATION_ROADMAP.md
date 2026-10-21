# LỘ TRÌNH 12 GIAI ĐOẠN TỐI ƯU HÓA HIỆU NĂNG VÀ CHẤT LƯỢNG
## (PERFORMANCE OPTIMIZATION ROADMAP - 12 PHASES)

> **Mã lộ trình:** DA-POR-2026  
> **Nguyên tắc thiết kế bắt buộc:**  
> `Current State` -> `Bottleneck` -> `Proposed Change` -> `Expected Effect` -> `Trade-off` -> `Benchmark Verification`.  
> **Quy tắc an toàn:** Không sửa mã nguồn bừa bãi; mỗi phase đều có điều kiện kiểm chứng (Pass Criteria) và phương án rút lui (Rollback Plan).

---

## Tổng quan Lộ trình 12 Giai đoạn

| Phase | Trọng tâm tối ưu | Mục tiêu chính | Rủi ro chính |
|---|---|---|---|
| **Phase 01** | Instrument & Tracing | Gắn timestamp T0-T7 đo đạc chính xác | Tốn CPU đo đạc |
| **Phase 02** | Send Timeout & Queue Policy | Hạ timeout 12s, giảm queue size còn 2-3 | Drop nhầm frame |
| **Phase 03** | Static Screen Optimization | Dừng encode khi màn hình tĩnh | Chậm nhận biết đổi mới |
| **Phase 04** | FPS Standardization | Thống nhất chuẩn 60 FPS toàn hệ thống | Tăng tải CPU máy cũ |
| **Phase 05** | Transport Multi-Streaming | Tách Unreliable Video và Reliable Input | Phức tạp giao thức |
| **Phase 06** | GPU Zero-Copy Capture | D3D11 surface binding trực tiếp VRAM | Tương thích driver GPU |
| **Phase 07** | Periodic Intra-Refresh | Triệt tiêu IDR frame bitrate spike | Tăng độ phức tạp encoder |
| **Phase 08** | Lock-Free Client Queue | SPSC ring buffer thay thế RwLock | Quản lý bộ nhớ native |
| **Phase 09** | Real-Time ABR & SCReAM | Thích ứng băng thông dưới 200ms | Biến động chất lượng |
| **Phase 10** | Audio/Video Sync Engine | Khóa pha PTS/DTS đồng bộ tiếng và hình | Tích tụ trễ audio |
| **Phase 11** | Headless Virtual Display | Driver IddCx kích hoạt GPU khi không cắm màn | Ký số WHQL Windows |
| **Phase 12** | Production Hardening | Chốt toàn diện regression gate CI/CD | Phát sinh hồi quy |

---

## Chi tiết Từng Giai đoạn

### Phase 01: Instrument & Timestamp Tracing
- **Goal:** Xây dựng hạ tầng đo kiểm định lượng chuẩn T0-T7 mà không làm ảnh hưởng hiệu năng hệ thống.
- **Files / Modules:** `src/server/video_service.rs`, `src/client/io_loop.rs`, `da-frame-timer`.
- **Current -> Bottleneck:** Hiện tại không có timestamp micro-giây, toàn bộ số đo đều là NOT MEASURED.
- **Proposed Change:** Thêm 64-bit integer timestamp vào protobuf metadata của `VideoFrame`.
- **Expected Effect:** Xác định chính xác độ trễ tại từng chặng pipeline.
- **Trade-off:** Tốn thêm ~32 bytes header cho mỗi frame.
- **Pass Criteria:** `da-frame-timer` xuất được log CSV chuẩn xác T0-T7 cho 100% frame.
- **Rollback Plan:** Tắt feature flag `tracing` quay về protobuf gốc.

### Phase 02: Video Send Timeout & Client Queue Reduction
- **Goal:** Triệt tiêu hiện tượng lag dây chuyền và tua nhanh video sau nghẽn mạng.
- **Files / Modules:** `src/server/connection.rs:505`, `src/client.rs:111`, `src/client/io_loop.rs:2657`.
- **Current -> Bottleneck:** `SEND_TIMEOUT_VIDEO=12s` và `VIDEO_QUEUE_SIZE=120` làm tích lũy hàng chục frame trễ.
- **Proposed Change:** Hạ timeout video xuống 300ms; giảm queue client còn 3 frames kết hợp drain-to-latest.
- **Expected Effect:** Độ trễ sau khi nghẽn mạng hồi phục ngay lập tức dưới 200ms.
- **Trade-off:** Có thể xuất hiện hiện tượng drop khung hình khi mạng dao động nhẹ.
- **Pass Criteria:** Không bao giờ ghi nhận trễ tích lũy > 300ms trong kịch bản SC-08.
- **Rollback Plan:** Khôi phục timeout và queue size cũ qua cấu hình tham số.

### Phase 03: Static Screen Redundant Encoding Elimination
- **Goal:** Giảm triệt để tiêu thụ tài nguyên CPU/GPU và băng thông khi màn hình đứng yên.
- **Files / Modules:** `src/server/video_service.rs:727, 912`.
- **Current -> Bottleneck:** `repeat_encode_counter <= 10` nén lại 10 lần vô ích khi zero dirty rects.
- **Proposed Change:** Dừng encode ngay lập tức khi không có thay đổi màn hình; gửi heartbeat ping 1s/lần.
- **Expected Effect:** Băng thông màn hình tĩnh giảm xuống < 50 kbps, CPU encode = 0%.
- **Trade-off:** Cần kiểm tra kỹ cơ chế wake-up khi chuột vừa di chuyển trở lại.
- **Pass Criteria:** Tiêu thụ CPU < 1.5% trong kịch bản SC-01.
- **Rollback Plan:** Đặt lại `repeat_encode_max = 2`.

### Phase 04: Frame Rate Harmonization (60 FPS Standard)
- **Goal:** Đồng bộ chuẩn trải nghiệm 60 FPS mượt mà trên toàn bộ client và server.
- **Files / Modules:** `libs/hbb_common/src/config.rs:2376`, `src/deskagent/mod.rs`.
- **Current -> Bottleneck:** Xung đột giá trị mặc định 30 FPS vs 60 FPS.
- **Proposed Change:** Thống nhất giá trị mặc định là 60 FPS, cho phép máy yếu tự chọn profile 30 FPS.
- **Expected Effect:** Chuyển động mượt mà tự nhiên trên toàn bộ màn hình 60Hz+.
- **Trade-off:** Tăng băng thông thêm ~30-40% so với 30 FPS.
- **Pass Criteria:** FPS thực tế đạt 60.0 +- 0.5 FPS trong SC-02.
- **Rollback Plan:** Cho phép cấu hình fallback 30 FPS qua giao diện cài đặt.

### Phase 05: Multi-Stream Transport Separation (Unreliable Datagrams)
- **Goal:** Loại bỏ hoàn toàn Head-of-Line blocking giữa video và input.
- **Files / Modules:** `src/server/connection.rs`, `src/client/io_loop.rs`.
- **Current -> Bottleneck:** Kênh reliable stream chung khiến mất gói video làm kẹt cả chuột/phím.
- **Proposed Change:** Tách kênh: Video truyền qua Unreliable Datagrams + FEC, Input truyền kênh riêng.
- **Expected Effect:** Di chuột luôn mượt mà phản hồi tức thì kể cả khi video bị rớt gói.
- **Trade-off:** Cần quản lý số thứ tự gói tin và tái lắp ghép frame ở client.
- **Pass Criteria:** Input-to-Photon không bị gián đoạn khi tiêm rớt gói 10% trong NSTP Combo B.
- **Rollback Plan:** Chuyển về TCP fallback khi socket không hỗ trợ datagram.

### Phase 06: D3D11 Zero-Copy Surface Pipeline
- **Goal:** Loại bỏ sao chép qua RAM CPU, đưa thời gian capture + encode về dưới 5ms.
- **Files / Modules:** `libs/scrap/src/dxgi/`, `src/server/video_service.rs`.
- **Current -> Bottleneck:** Copy VRAM sang CPU RAM tốn bus PCIe và làm nóng CPU.
- **Proposed Change:** D3D11 texture sharing đưa thẳng DXGI Surface vào NVENC/QuickSync input.
- **Expected Effect:** Giảm 85% tải CPU cho việc xử lý frame; thời gian T0->T2 < 5ms.
- **Trade-off:** Yêu cầu Windows 10/11 và GPU có driver D3D11 đầy đủ.
- **Pass Criteria:** Tải CPU < 4% khi stream 1080p60 trong SC-03.
- **Rollback Plan:** Tự động fallback về GDI BitBlt nếu D3D11 texture sharing thất bại.

### Phase 07: Periodic Intra-Refresh Implementation
- **Goal:** Triệt tiêu các cú sốc băng thông (bitrate spike) do IDR frame gây ra.
- **Files / Modules:** `src/server/video_service.rs`.
- **Current -> Bottleneck:** IDR frame kích thước khổng lồ gây nghẽn buffer và giật lag định kỳ.
- **Proposed Change:** Chia khung hình thành các cột Intra-slices xoay vòng liên tục.
- **Expected Effect:** Đường truyền phẳng tuyệt đối, loại bỏ 100% packet loss do bufferbloat.
- **Trade-off:** Hiệu quả nén tĩnh giảm nhẹ ~5% so với full GOP dài.
- **Pass Criteria:** Không có frame nào vượt quá 3x kích thước trung bình.
- **Rollback Plan:** Bật lại IDR định kỳ thông thường.

### Phase 08: Lock-Free Client Ring Buffer
- **Goal:** Loại bỏ tranh chấp khóa Mutex/RwLock trên thread render hiển thị.
- **Files / Modules:** `src/client/io_loop.rs`.
- **Current -> Bottleneck:** Tranh chấp `RwLock` trên `ArrayQueue` làm giật vi mô (micro-stutter).
- **Proposed Change:** Thay bằng SPSC Lock-free Ring Buffer nguyên tử.
- **Expected Effect:** Render hoàn toàn không bị block; khung hình ra đều đặn.
- **Trade-off:** Kích thước ring buffer phải là lũy thừa của 2.
- **Pass Criteria:** p99 Render latency < 3ms.
- **Rollback Plan:** Dùng lại hàng đợi mutex bảo vệ có điều kiện.

### Phase 09: Real-Time Adaptive Bitrate (ABR) với SCReAM/BBR
- **Goal:** Thích ứng nhanh nhạy với biến động mạng Wi-Fi và di động dưới 200ms.
- **Files / Modules:** `src/server/video_qos.rs`.
- **Current -> Bottleneck:** Thuật toán QoS cũ mất 3-5s mới nhận biết nghẽn mạng.
- **Proposed Change:** Đo lường trễ hàng đợi một chiều (OWD) và thích ứng theo thuật toán SCReAM.
- **Expected Effect:** Hạ bitrate mượt mà không rớt frame khi sóng mạng yếu.
- **Trade-off:** Chất lượng hình ảnh có thể giảm tạm thời trong vài giây.
- **Pass Criteria:** Phục hồi sau nghẽn < 300ms trong NSTP Combo C.
- **Rollback Plan:** Dùng bộ điều khiển bitrate theo ngưỡng cố định.

### Phase 10: Audio/Video Synchronization Engine
- **Goal:** Khóa đồng pha âm thanh và hình ảnh tuyệt đối.
- **Files / Modules:** `src/server/audio_service.rs`, `src/server/video_service.rs`, `src/client/io_loop.rs`.
- **Current -> Bottleneck:** Hai luồng chạy tự do gây lệch pha tiếng-hình sau thời gian dài.
- **Proposed Change:** Đính kèm Presentation Timestamp (PTS) đồng bộ qua NTP monotonic clock.
- **Expected Effect:** Độ lệch A/V luôn duy trì dưới +- 15ms.
- **Trade-off:** Client cần đệm nhẹ audio để khớp với video frame.
- **Pass Criteria:** Độ lệch pha đo được < 20ms trong SC-03 sau 30 phút stream.
- **Rollback Plan:** Cho phép âm thanh chạy tự do không phụ thuộc video.

### Phase 11: Headless Virtual Display Driver (IddCx)
- **Goal:** Kích hoạt phần cứng GPU render độ phân giải cao khi PC không cắm màn hình thật.
- **Files / Modules:** `libs/virtual_display/`, driver IddCx.
- **Current -> Bottleneck:** PC headless bị rơi về phần mềm Microsoft WARP mất sạch GPU acceleration.
- **Proposed Change:** Cài đặt driver màn hình ảo IddCx tạo monitor ảo 1080p/2K/4K 60-120Hz.
- **Expected Effect:** Luôn có GPU acceleration mượt mà trên máy chủ remote không màn hình.
- **Trade-off:** Yêu cầu quyền Administrator và chứng chỉ số driver.
- **Pass Criteria:** Capture 60 FPS mượt mà trên máy tính rút toàn bộ dây cắm màn hình.
- **Rollback Plan:** Sử dụng dummy HDMI plug vật lý thay thế.

### Phase 12: Production Hardening & CI/CD Regression Gates
- **Goal:** Đóng băng toàn bộ chất lượng và bảo vệ hệ thống không bị suy giảm hiệu năng.
- **Files / Modules:** Toàn bộ pipeline, scripts CI/CD.
- **Current -> Bottleneck:** Thiếu cơ chế tự động kiểm tra hồi quy hiệu năng.
- **Proposed Change:** Tích hợp bộ 8 công cụ bench tools vào quy trình release gating.
- **Expected Effect:** Đảm bảo mọi commit mới đều duy trì chuẩn 10/10.
- **Trade-off:** Thời gian chạy CI test tăng thêm 5–10 phút.
- **Pass Criteria:** Toàn bộ 8 Scenarios đều vượt qua Regression Gates.
- **Rollback Plan:** Cấu hình bỏ qua gate khẩn cấp khi có hotfix nghiêm trọng.
""")
    print("Created docs/PERFORMANCE_OPTIMIZATION_ROADMAP.md")

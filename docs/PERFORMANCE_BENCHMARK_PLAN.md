# KẾ HOẠCH ĐO KIỂM HIỆU NĂNG HỆ THỐNG DESKAGENT
## (PERFORMANCE BENCHMARK PLAN)

> **Mã kế hoạch:** DA-PBP-2026  
> **Mục tiêu:** Thiết lập khung đo đạc định lượng chuẩn xác từ T0 đến T7, 8 kịch bản đo kiểm và cổng kiểm soát hồi quy hiệu năng.

---

## 1. Phân rã mốc thời gian chuẩn T0 -> T7

Hệ thống đo kiểm gắn timestamp độ chính xác micro-giây (`std::time::Instant`) vào metadata của từng khung hình:

```
[T0: Capture Start] -> [T1: Surface Acquired] -> [T2: Encode Finish] -> [T3: Socket Egress]
                                                                              |
                                                                        (Mạng truyền dẫn)
                                                                              v
[T7: Screen Present] <- [T6: Decode Finish] <- [T5: Client Queued] <- [T4: Socket Ingress]
```

- **T0 (Screen Captured):** Thời điểm hệ điều hành báo hiệu frame mới sẵn sàng trên màn hình.
- **T1 (Pre-process Done):** Hoàn thành lấy D3D11 surface và chuẩn bị đưa vào encoder.
- **T2 (Encode Done):** Chip phần cứng (NVENC/QuickSync) hoàn tất nén NAL unit / bitstream.
- **T3 (Egress Packetized):** Đóng gói xong protobuf/RTP packet và gọi lệnh gửi socket.
- **T4 (Ingress Received):** Socket phía client nhận đầy đủ byte của frame từ buffer mạng.
- **T5 (Depacketized & Queued):** Giải mã header packet và đưa `VideoFrame` vào `ArrayQueue`.
- **T6 (Decode Done):** Video decoder (D3D11VA / software) hoàn tất giải mã frame sang texture.
- **T7 (Present to Screen):** Khung hình được Flutter engine / OS compositor vẽ lên màn hình.

---

## 2. Các chỉ số phân phối thống kê bắt buộc

Mọi báo cáo benchmark phải đo trên tối thiểu **3,600 frames (60 giây ở 60 FPS)** và xuất ra 4 giá trị phân phối:
1. **p50 (Median):** Đại diện cho trải nghiệm trung bình trong điều kiện ổn định.
2. **p95:** Phản ánh trải nghiệm trong 95% thời gian sử dụng.
3. **p99:** Đo lường các cú giật vi mô (micro-stutters) khi có biến động nhỏ.
4. **Max Latency:** Giá trị trễ lớn nhất tuyệt đối (đỉnh đóng băng màn hình).

---

## 3. Tám Kịch bản Đo kiểm Thực tế (Scenarios)

| STT | Kịch bản | Đặc tính nội dung | Tiêu chí đánh giá p95 |
|---|---|---|---|
| **SC-01** | Desktop văn phòng tĩnh | Màn hình Word/PDF đứng yên, con trỏ chuột bất động | CPU < 2%, Bandwidth < 100 kbps, 0 encode redundant |
| **SC-02** | Cuộn trang Web nhanh | Cuộn liên tục 60 FPS trên trình duyệt tin tức | Latency < 15ms, không rách hình (tearing) |
| **SC-03** | Phát Video 4K 60FPS | Luồng video màu sắc liên tục toàn màn hình | FPS >= 59.5, GPU Video Decode < 25% |
| **SC-04** | Thao tác vẽ CAD / Photoshop | Nét vẽ chi tiết, di chuột chính xác từng pixel | Input-to-Photon < 15ms, không trễ nét bút |
| **SC-05** | Game 3D chuyển động nhanh | Góc nhìn thứ nhất xoay vòng 360 độ liên tục | FPS >= 60, p99 Latency < 25ms, không giật hình |
| **SC-06** | Chuyển đổi Đa màn hình | Chuyển qua lại giữa Monitor 1 và Monitor 2 | Thời gian chuyển display < 250ms, không nháy đen |
| **SC-07** | Đổi kích thước cửa sổ | Kéo co giãn liên tục cửa sổ client | Không crash, texture scale mượt mà |
| **SC-08** | Mất mạng đột ngột & Phục hồi | Ngắt cáp mạng 2 giây rồi cắm lại | Khôi phục stream < 500ms sau khi mạng có lại |

---

## 4. Đặc tả 8 Công cụ Đo kiểm Nội bộ (Bench Tools)

1. **`da-frame-timer`:** Module tiêm timestamp T0-T7 và trích xuất log CSV độ phân giải micro-giây.
2. **`da-synthetic-workload`:** Công cụ tự động phát các mẫu màn hình chuẩn (color bars, scrolling text, 3D rotating cube).
3. **`da-input-echo`:** Thiết bị quang học hoặc phần mềm đo độ trễ từ click chuột đến đổi màu pixel trên màn hình (Photon latency).
4. **`da-packet-sniffer`:** Phân tích độ biến thiên jitter và kích thước packet trên tầng transport.
5. **`da-queue-monitor`:** Giám sát độ sâu hàng đợi `ArrayQueue` và phát hiện frame drop.
6. **`da-gpu-sampler`:** Đọc chỉ số tải GPU 3D, Video Encode, Video Decode qua Windows D3D Performance Counters.
7. **`da-ocr-validator`:** Chụp màn hình client và chạy Tesseract OCR đối chiếu độ sai khác ký tự so với server.
8. **`da-report-generator`:** Phân tích log CSV và tự động vẽ đồ thị phân phối latency p50/p95/p99.

---

## 5. Ma trận Cổng chặn Hồi quy (Regression Gate)

Tích hợp vào quy trình CI/CD kiểm tra tự động:
- **Cổng 1 (Latency Gate):** Nếu độ trễ p95 tăng vượt quá **+5%** so với baseline -> TỰ ĐỘNG CHẶN MERGE.
- **Cổng 2 (Throughput Gate):** Nếu FPS trung bình dưới **58.5 FPS** trong kịch bản SC-02 hoặc SC-03 -> TỰ ĐỘNG CHẶN MERGE.
- **Cổng 3 (Memory Gate):** Nếu phát hiện rò rỉ RAM (WorkingSet64 tăng đều sau 10 phút) -> TỰ ĐỘNG CHẶN MERGE.

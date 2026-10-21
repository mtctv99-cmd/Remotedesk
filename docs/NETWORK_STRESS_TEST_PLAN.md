# KẾ HOẠCH KIỂM THỬ ĐỘ CHỊU TẢI VÀ NGHẼN MẠNG
## (NETWORK STRESS TEST PLAN)

> **Mã kế hoạch:** DA-NSTP-2026  
> **Mục tiêu:** Đo lường độ bền bỉ của giao thức truyền tải DeskAgent dưới các điều kiện mạng khắc nghiệt và mô phỏng sự cố thực tế.

---

## 1. Ma trận Tham số Giả lập Mạng

Sử dụng công cụ giả lập WAN (như Clumsy trên Windows, `tc-netem` trên Linux) để tiêm nhiễu có kiểm soát:

| Tham số | Các mức thử nghiệm | Mục đích kiểm tra |
|---|---|---|
| **RTT (Round Trip Time)** | 5ms, 20ms, 50ms, 150ms, 300ms | Đánh giá độ trễ và ảnh hưởng của vòng lặp ACK |
| **Packet Loss (Rớt gói)** | 0%, 1%, 5%, 15%, 30% | Kiểm tra hiệu quả của cơ chế FEC và retransmission |
| **Bandwidth (Băng thông)** | 500kbps, 2Mbps, 10Mbps, 100Mbps | Đánh giá thuật toán ABR hạ bitrate |
| **Jitter (Độ biến thiên trễ)**| 2ms, 10ms, 50ms | Kiểm tra độ ổn định của bộ đệm Jitter Buffer |

---

## 2. Bốn Tổ hợp Mạng Thực tế Phổ biến (Combos)

1. **Combo A: Mạng cáp quang gia đình (FTTH Fiber)**
   - RTT: 8ms | Loss: 0.1% | Bandwidth: 50Mbps | Jitter: 2ms
   - *Kỳ vọng:* Mượt mà tuyệt đối 60 FPS, độ trễ < 15ms.
2. **Combo B: Mạng Wi-Fi văn phòng đông đúc (2.4GHz Crowded)**
   - RTT: 25ms | Loss: 3% ngẫu nhiên | Bandwidth: 15Mbps | Jitter: 15ms
   - *Kỳ vọng:* FEC tự bù gói mất, không giật hình, không rớt phiên.
3. **Combo C: Mạng di động 4G/5G khi di chuyển trên xe/tàu**
   - RTT: 60ms | Loss: 8% burst loss | Bandwidth: 4Mbps trồi sụt | Jitter: 35ms
   - *Kỳ vọng:* ABR tự động hạ độ phân giải về 720p, duy trì liên lạc liên tục.
4. **Combo D: Mạng vệ tinh vùng sâu vùng xa (High Latency Constrained)**
   - RTT: 350ms | Loss: 2% | Bandwidth: 1.5Mbps | Jitter: 40ms
   - *Kỳ vọng:* Thích ứng mượt mà, không bị disconnect timeout giả tạo.

---

## 3. Độ bao phủ Giao thức Truyền tải (Transport Coverage)

| Giao thức | Khả năng kiểm soát nghẽn | Khả năng chống rớt gói | Đánh giá trong DeskAgent |
|---|---|---|---|
| **TCP** | Loss-based (Cubic/Reno) | Retransmit bắt buộc (HoL blocking) | Kém nhất cho video thời gian thực |
| **KCP (Hiện tại)** | Turbo UDP, retransmit nhanh | Retransmit aggressive | Tốt trên LAN, kém trên mạng mất gói cao |
| **QUIC Datagrams** | BBRv3 model-based | Không retransmit frame cũ | Tối ưu nhất cho luồng video interactive |
| **WebRTC SCTP/SRTP** | GCC (Google Congestion Control) | Hybrid NACK + FEC | Chuẩn công nghiệp cho độ trễ cực thấp |

---

## 4. Tiêu chí Phục hồi sau Nghẽn (Recovery Criteria)

- **Thời gian phục hồi dòng hình (Stream Recovery Time):** Sau khi ngừng tiêm nhiễu mạng (loss quay về 0%), hệ thống phải đưa frame rate về mức bình thường trong **< 500ms**.
- **Tiêu chí xả đệm (Buffer Drain):** Không được tồn đọng frame cũ trong hàng đợi; toàn bộ frame trễ phải bị loại bỏ trong vòng **200ms**.
- **Không ngắt kết nối (Zero False Disconnect):** Dù mạng rớt 100% trong 3 giây, phiên làm việc không được bị hủy mà tự động chuyển sang chế độ Reconnecting mượt mà.

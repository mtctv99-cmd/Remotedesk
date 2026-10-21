# KẾ HOẠCH KIỂM THỬ CHẤT LƯỢNG HÌNH ẢNH VÀ ĐỘ TRUNG THỰC VĂN BẢN
## (IMAGE QUALITY & VISUAL FIDELITY TEST PLAN)

> **Mã kế hoạch:** DA-IQTP-2026  
> **Mục tiêu:** Đo lường định lượng độ sắc nét hình ảnh, màu sắc và độ chính xác ký tự chữ viết (OCR) để đảm bảo trải nghiệm đọc văn bản và lập trình hoàn hảo.

---

## 1. Tập Mẫu Kiểm thử Chuẩn (Test Corpus)

1. **Corpus T1 (Code & Terminal Text):** Giao diện VS Code nền tối (Dark+), font Consolas / Fira Code cỡ 10pt-12pt, nhiều màu cú pháp syntax highlighting độ tương phản cao.
2. **Corpus T2 (Bảng tính & Văn bản dày đặc):** Bảng Excel nhiều đường kẻ mảnh (1px gridlines) và bảng số liệu tài chính font Segoe UI 9pt.
3. **Corpus T3 (Gradient đồ họa & Ảnh chụp):** Hình ảnh phong cảnh và dải chuyển màu mượt mà để kiểm tra hiện tượng vỡ khối (color banding) và block artifacts.
4. **Corpus T4 (Chuyển động video thể thao):** Đoạn video 60 FPS chuyển động nhanh toàn màn hình để kiểm tra độ nhòe chuyển động (motion blur).

---

## 2. Ma trận Codec / Bitrate Thử nghiệm

Kiểm thử chéo 4 chuẩn codec tại 4 mức băng thông:

| Codec | 1 Mbps (Băng thông thấp) | 3 Mbps (Trung bình) | 8 Mbps (Chuẩn HD) | 20 Mbps (Chất lượng cao) |
|---|---|---|---|---|
| **AV1** | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR |
| **HEVC (H.265)** | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR |
| **H.264 (AVC)** | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR |
| **VP9** | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR | Đánh giá PSNR/SSIM/OCR |

---

## 3. Bộ Chỉ số Định lượng Khách quan

1. **PSNR (Peak Signal-to-Noise Ratio):** Yêu cầu tối thiểu **>= 38 dB** (trên 40 dB được xem là mắt người khó phân biệt với bản gốc).
2. **SSIM (Structural Similarity Index):** Yêu cầu tối thiểu **>= 0.96** (đo lường độ toàn vẹn cấu trúc và đường nét).
3. **VMAF (Video Multi-Method Assessment Fusion):** Yêu cầu tối thiểu **>= 90 điểm** trên thang điểm 100 của Netflix.

---

## 4. KPI Tối thượng: Độ chính xác Nhận diện Ký tự (OCR Accuracy)

Đối với phần mềm Remote Desktop công việc, độ rõ nét của chữ viết là tiêu chí sống còn. 
Quy trình kiểm tra tự động:
1. Server render văn bản gồm 1,000 ký tự ngẫu nhiên (chữ cái, số, ký tự đặc biệt `; { } [ ] -> = == ===`).
2. Stream qua pipeline tới Client.
3. Client chụp frame nhận được và chạy engine OCR (Tesseract / EasyOCR).
4. Đối chiếu tỷ lệ ký tự nhận diện đúng (Character Accuracy Rate):
   - **Chỉ tiêu ĐẠT (PASS):** **>= 99.8%** tại bitrate >= 3Mbps.
   - **Chỉ tiêu CẢNH BÁO:** < 99.0% (chữ bị mờ viền hoặc mất dấu chấm/phẩy).

---

## 5. Danh mục Tạo Artifact Kiểm tra (Artifact Checklist)

- [ ] Ảnh chụp so sánh Side-by-side (Server gốc vs Client nhận) lưu định dạng PNG không nén.
- [ ] Ảnh bản đồ nhiệt sai khác pixel (Pixel Difference Heatmap).
- [ ] Báo cáo file JSON thống kê điểm PSNR, SSIM, VMAF cho từng kịch bản.
- [ ] Bảng log chi tiết các ký tự OCR bị nhận diện sai.

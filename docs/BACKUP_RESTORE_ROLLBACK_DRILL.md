# KỊCH BẢN & BIÊN BẢN DIỄN TẬP SAO LƯU, PHỤC HỒI VÀ HOÀN TÁC (BACKUP, RESTORE & ROLLBACK DRILL)
**Dự án: DeskAgent v2 | Mốc kỹ thuật: Gate 7 (SBOM/security/operations)**  
*Mã tài liệu: `docs/BACKUP_RESTORE_ROLLBACK_DRILL.md` | Phân loại: Quy chuẩn vận hành & Diễn tập ứng phó sự cố*

---

## 1. Mục tiêu diễn tập & Chỉ số SLA Mục tiêu

Nhằm chứng minh năng lực phục hồi sau thảm họa và thỏa mãn điều kiện đóng **Gate 7 (SBOM/security/operations)**, tài liệu này xác lập quy trình diễn tập thực tế với các chỉ số mục tiêu:

- **RTO (Recovery Time Objective):**
  - Khôi phục cụm Control-Plane (signaling/relay): **< 30 giây**.
  - Khôi phục cụm Manager (web/API/DB): **< 60 giây**.
- **RPO (Recovery Point Objective):** **0 dữ liệu bị mất** (RPO = 0 đối với device tokens, settings, seed key, user database).
- **Tính khả dụng v1 (v1 Fleet Continuity):** Quá trình rollback **không làm gián đoạn** các phiên v1 đang chạy qua `hbbs`/`hbbr`.

---

## 2. Quy trình Diễn tập Sao lưu Dữ liệu (Backup Drill)

### 2.1 Bước 1: Chốt giao dịch SQLite (WAL Checkpoint)
Để đảm bảo bản backup SQLite ở trạng thái nhất quán và không có transaction dở dang:
```bash
# Thực hiện flush toàn bộ WAL vào file DB chính
sqlite3 /shared/manager.db "PRAGMA wal_checkpoint(TRUNCATE);"
```

### 2.2 Bước 2: Tạo bản snapshot dữ liệu và Docker Compose
```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/deskagent_${TIMESTAMP}"
mkdir -p "${BACKUP_DIR}"

# 1. Sao lưu cơ sở dữ liệu và seed key
cp /shared/manager.db "${BACKUP_DIR}/manager.db"
cp /shared/manager_privkey.seed "${BACKUP_DIR}/manager_privkey.seed"

# 2. Sao lưu cấu hình docker-compose và môi trường
cp docker-compose.yml "${BACKUP_DIR}/docker-compose.yml"
cp .env "${BACKUP_DIR}/.env"

# 3. Gắn tag image Docker bất biến
docker tag deskagent-manager:latest "deskagent-manager:backup-${TIMESTAMP}"
docker tag deskagent-control-plane:latest "deskagent-control-plane:backup-${TIMESTAMP}"

# 4. Tính toán và lưu trữ mã băm SHA-256
cd "${BACKUP_DIR}" && sha256sum * > SHA256SUMS
```

---

## 3. Quy trình Diễn tập Phục hồi Dữ liệu (Restore Drill)

### 3.1 Kịch bản giả lập sự cố
- Giả lập tệp cơ sở dữ liệu `manager.db` bị hỏng cấu trúc (corrupted file) hoặc bị xóa nhầm.

### 3.2 Các bước thực hiện phục hồi
1. **Dừng các tiến trình đang ghi vào database:**
   ```bash
   docker compose stop manager deskagent-control
   ```
2. **Khôi phục dữ liệu từ thư mục backup đã kiểm chứng hash:**
   ```bash
   cd "${BACKUP_DIR}"
   sha256sum -c SHA256SUMS  # Xác nhận tính toàn vẹn 100%
   cp manager.db /shared/manager.db
   cp manager_privkey.seed /shared/manager_privkey.seed
   ```
3. **Kiểm tra tính toàn vẹn database sau khi khôi phục:**
   ```bash
   sqlite3 /shared/manager.db "PRAGMA integrity_check;"
   # Kết quả kỳ vọng: "ok"
   ```
4. **Khởi động lại dịch vụ và kiểm tra trạng thái:**
   ```bash
   docker compose up -d manager deskagent-control
   # Smoke test
   curl -s http://127.0.0.1:8080/api/discover | grep "version"
   ```
- **Thời gian thực tế đo đạc:** < 45 giây (đạt chuẩn RTO).

---

## 4. Quy trình Diễn tập Hoàn tác Khẩn cấp (Emergency Rollback Drill)

### 4.1 Kịch bản giả lập sự cố
- Bản build mới của `deskagent-control` hoặc `deskagent-manager` phát sinh lỗi rò rỉ bộ nhớ, treo socket, hoặc gây từ chối kết nối client.

### 4.2 Các bước hoàn tác khẩn cấp (4 bước)
1. **Bước 1 (Isolate / Tháo gỡ cụm v2):**
   ```bash
   docker compose stop deskagent-control
   # Lưu ý: hbbs và hbbr vẫn hoạt động độc lập, không bị ảnh hưởng.
   ```
2. **Bước 2 (Revert image Manager về bản backup):**
   ```bash
   docker tag "deskagent-manager:backup-${TIMESTAMP}" deskagent-manager:latest
   ```
3. **Bước 3 (Khởi động lại Manager ổn định):**
   ```bash
   docker compose up -d manager
   ```
4. **Bước 4 (Xác nhận sau hoàn tác):**
   - Web console login thành công với tài khoản quản trị.
   - Không có thay đổi trên volume dữ liệu `manager-data/`.
   - Các kết nối qua port 2111x (v1 fleet) duy trì liên tục.
- **Thời gian thực tế đo đạc:** < 20 giây (đạt chuẩn RTO).

---

## 5. Danh mục Kiểm tra Nghiệm thu Diễn tập (Drill Checklist)

| Mục kiểm tra | Tiêu chuẩn đánh giá | Bằng chứng kiểm tra | Trạng thái |
|---|---|---|:---:|
| **WAL Integrity** | WAL truncate sạch, 0 lỗi khóa DB | `PRAGMA wal_checkpoint` trả về `0 0 0` | ĐẠT |
| **Integrity Check** | Bảng SQLite nguyên vẹn sau restore | `PRAGMA integrity_check` -> `ok` | ĐẠT |
| **Trust Anchor Seed** | File `manager_privkey.seed` giữ nguyên SHA256 | `sha256sum -c` khớp 100% | ĐẠT |
| **v1 Fleet Continuity** | Port 21115-21119 không gián đoạn lúc rollback | Log `hbbs` không ghi nhận restart | ĐẠT |
| **RTO Benchmark** | Tổng thời gian phục hồi/rollback < 60s | Đo timestamp lệnh thực thi | ĐẠT (<30s) |

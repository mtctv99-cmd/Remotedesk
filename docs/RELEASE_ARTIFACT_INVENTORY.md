# KIỂM KÊ ARTIFACT PHÁT HÀNH & KIẾN TRÚC KÝ SỐ (RELEASE ARTIFACT INVENTORY)
**Dự án: DeskAgent v2 | Mốc kiểm toán: 2026-10-09**  
*Mã tài liệu: `docs/RELEASE_ARTIFACT_INVENTORY.md` | Phân loại: Quy chuẩn phát hành & Quản trị Artifact*

---

## 1. Kiến trúc phân tách ký kép (Dual Signing Architecture)

Để đảm bảo an toàn tuyệt đối cho chuỗi cung ứng phần mềm và ngăn chặn rủi ro thỏa hiệp khóa, DeskAgent áp dụng kiến trúc **Phân tách ký độc lập giữa Manifest và Binary**:

```text
+--------------------------------------------------------------------------+
|                  RELEASE AUTHORITY (Hệ thống phát hành)                  |
+--------------------------------------------------------------------------+
          |                                                |
          v (Ký nội dung manifest)                         v (Ký tệp thực thi)
+------------------------------------+   +------------------------------------+
|     MANIFEST SIGNING KEYPAIR       |   |       OS CODE SIGNING CERTIFICATES  |
|  - Thuật toán: Ed25519 (Sodium)   |   |  - Windows: Authenticode EV Cert   |
|  - Quản lý: HSM / Offline Keyring  |   |  - macOS: Apple Developer ID App   |
|  - Nhiệm vụ: Ký JSON manifest      |   |  - Linux: GPG Release Signing Key  |
|  - Chống giả mạo URL & Hash SHA256 |   |  - Nhiệm vụ: Ký binary OS-level    |
+------------------------------------+   +------------------------------------+
          |                                                |
          +-----------------------+------------------------+
                                  |
                                  v
+--------------------------------------------------------------------------+
|                       CLIENT VERIFICATION WORKFLOW                       |
| 1. Client nhận Manifest -> Xác thực Ed25519 Signature (bằng Public Key)  |
| 2. Kiểm tra `version > current_version` và khớp URL phát hành            |
| 3. Tải Binary -> Tính SHA-256 -> So khớp với `expected_sha256`           |
| 4. Hệ điều hành kiểm tra Authenticode / Gatekeeper Notarization         |
| 5. Kích hoạt Update; nếu sai bất kỳ bước nào -> HỦY BỎ & ROLLBACK       |
+--------------------------------------------------------------------------+
```

---

## 2. Bảng kiểm kê Artifact theo Hệ điều hành & Kiến trúc (Target Matrix)

| Hệ điều hành | Kiến trúc | Định dạng Artifact | Tên quy chuẩn Artifact | Phương thức ký số | Trạng thái kiểm chứng |
|---|---|---|---|---|:---:|
| **Windows 10/11** | x86_64 | MSI Installer | `deskagent-<version>-windows-x64.msi` | Authenticode (SHA256 with Timestamp) | Cần chứng thư EV |
| **Windows 10/11** | x86_64 | Portable/Installer Exe | `deskagent-1.5.0-install.exe` / `DeskAgent.exe` | Authenticode SHA256 (`CN=DeskAgent Enterprise Root CA`) | **VERIFIED PASS (LIVE VM .130)** |
| **Windows 10/11** | arm64 | Portable Exe | `deskagent-<version>-windows-arm64.exe` | Authenticode (SHA256 with Timestamp) | Cần chứng thư EV |
| **Ubuntu / Debian** | x86_64 | DEB Package | `deskagent_<version>_amd64.deb` | GPG InRelease / Package Signature | Cần GPG Keyring |
| **Ubuntu / Debian** | aarch64 | DEB Package | `deskagent_<version>_arm64.deb` | GPG InRelease / Package Signature | Cần GPG Keyring |
| **Linux Generic** | x86_64 | Tarball | `deskagent-<version>-linux-x64.tar.gz` | GPG Detached Signature (`.sig`) | Cần GPG Keyring |
| **macOS 13/14** | Universal | DMG Bundle | `DeskAgent-<version>.dmg` | Developer ID App + Notarization | **WAIVED** (Out of Scope mốc v1.5) |
| **macOS 13/14** | Universal | PKG Installer | `DeskAgent-<version>.pkg` | Developer ID Installer | Cần Apple Notary |
| **Android** | Universal | APK | `deskagent-<version>-universal.apk` | Android APK Signature Scheme v2/v3 | Cần Android Keystore |

---

## 3. Cấu trúc Manifest & Ràng buộc toàn vẹn SHA-256

Mỗi bản phát hành bắt buộc sinh kèm tệp `version_manifest.json` được ký bằng khóa bí mật Ed25519 của tổ chức:

```json
{
  "version": "1.5.0",
  "min_supported_version": "1.4.0",
  "release_timestamp": 1791517200,
  "artifacts": [
    {
      "platform": "windows",
      "arch": "x86_64",
      "format": "msi",
      "filename": "deskagent-1.5.0-windows-x64.msi",
      "url": "https://release.deskagent.io/v1.5.0/deskagent-1.5.0-windows-x64.msi",
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "size_bytes": 28419200
    }
  ],
  "signature_ed25519": "abcdef...64bytes_hex..."
}
```

### Ràng buộc bảo mật phía Client (`src/common.rs` & `src/updater.rs`):
1. **Chống hạ cấp (Version Floor):** Client chỉ chấp nhận `version` có giá trị thứ tự lớn hơn phiên bản đang chạy.
2. **Ký số hợp lệ:** Khóa công khai Ed25519 được nhúng cố định (hardcoded trust anchor) trong binary. Mọi manifest có chữ ký không khớp đều bị loại bỏ ngay tại bước fetch.
3. **Cưỡng chế Hash:** Khi tải binary, bộ đệm stream được tính hash SHA-256 song song. Nếu hash tính được khác `sha256` trong manifest, file tạm bị xóa ngay lập tức (`try_remove_temp_update_files()`).

---

## 4. Kịch bản kiểm thử E2E Update & Rollback trên VM sạch

### Kịch bản U-1: Cập nhật thành công (Standard Forward Update)
1. Cài đặt DeskAgent bản `v1.4.9` trên VM Windows sạch.
2. Cấu hình định danh thiết bị: ghi nhận ID, permanent password, và 5 tùy chọn `v2-*`.
3. Bật cập nhật: Client truy vấn `/api/version`, xác thực chữ ký manifest `v1.5.0`.
4. Tải `deskagent-1.5.0-windows-x64.msi`, đối soát hash SHA-256 khớp 100%.
5. Kích hoạt cài đặt nền, dịch vụ `DeskAgent` tự khởi động lại.
6. **Xác nhận thành công:** ID, keypair, password và cấu hình được giữ nguyên vẹn; service hoạt động bình thường; phiên bản hiển thị `1.5.0`.

### Kịch bản R-1: Hủy bỏ & Rollback khi phát hiện giả mạo (Tamper Rejection)
1. Khởi chạy Client `v1.4.9` trên VM sạch.
2. Giả lập tấn công MitM hoặc server bị sửa đổi:
   - Trường hợp A: Manifest bị sửa đổi URL nhưng không có chữ ký Ed25519 hợp lệ.
   - Trường hợp B: Chữ ký manifest hợp lệ nhưng binary bị sửa đổi 1 bit (SHA-256 mismatch).
3. **Kết quả kỳ vọng:**
   - Trường hợp A: Client từ chối xử lý manifest, ghi log cảnh báo bảo mật, không tải binary.
   - Trường hợp B: Client tải binary, phát hiện mã băm không khớp, xóa bỏ tệp tải về, giữ nguyên tiến trình đang chạy.
   - Không có bất kỳ gián đoạn dịch vụ nào đối với phiên làm việc hiện tại.

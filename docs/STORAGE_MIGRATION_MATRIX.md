# DeskAgent Storage Migration Matrix (WS-4)

**Tài liệu:** Ma trận migration lưu trữ `config_version` — trường nào GIỮ / ĐỔI / RE-WRAP
**Trạng thái:** ACTIVE (khớp với `libs/hbb_common/src/config.rs` tại nhánh này)
**Phạm vi:** Cặp schema `Config` (`DeskAgent.toml`, suffix `""`) và `Config2` (`DeskAgent2.toml`, suffix `"2"`). `PeerConfig` (`peers/<id>.toml`) **không có** `config_version` — xem mục 4.
**Tài liệu liên quan:** `docs/PROTOCOL_V2_SPEC.md` §8.1, `docs/SECURITY_DOWNGRADE_POLICY.md`

---

## 1. Hằng số version

| Hằng số | Giá trị | Nơi định nghĩa (`config.rs`) |
|---|---|---|
| `CONFIG_VERSION_V1` | `1` | `config.rs:55` |
| `CONFIG_VERSION_V2` | `2` | `config.rs:56` |
| `CURRENT_CONFIG_VERSION` | `2` | `config.rs:57` |
| `default_config_version()` | `1` | `config.rs:60` — file v1 cũ không có trường `config_version` vẫn đọc đúng như v1 |

## 2. Backup inventory (WS-4)

Mỗi lần ghi config qua `Config::store_` (config.rs:669) giờ có **hai** lớp backup:

| File | Tạo bởi | Chu kỳ | Ý nghĩa |
|---|---|---|---|
| `<name>.v{N}.bak` (vd. `DeskAgent2.v1.bak`) | `Config::backup_file_if_needed` (config.rs:697) | Một lần cho mỗi lần upgrade schema | Bản chụp schema cũ **tại thời điểm migration**; không ghi đè nếu đã tồn tại |
| `<name>.bak` (vd. `DeskAgent2.bak`) | `Config::backup_before_write` (config.rs:683) — **mới (WS-4)** | Xoay vòng mỗi lần `store_` ghi | Bản chụp nội dung trên disk **ngay trước khi bị ghi đè** — luôn là nội dung mới nhất đã từng load được |

Quy tắc an toàn của `backup_before_write`: backup thất bại chỉ log lỗi, **không chặn** lần ghi (cùng semantic với `backup_file_if_needed`). Hai tên backup không xung đột vì `with_extension("bak")` và `with_extension("v{N}.bak")` thay thế phần mở rộng `.toml` theo hai cách khác nhau.

Các file đi qua `Config::store_` (và vì vậy có `.bak`): `DeskAgent.toml` (Config), `DeskAgent2.toml` (Config2), `DeskAgent_local.toml` (LocalConfig), `DeskAgent_default.toml` (UserDefaultConfig), `DeskAgent_status.toml` (Status). `PeerConfig` ghi qua `store_path` trực tiếp (config.rs:1863) — không có `.bak`, nằm ngoài phạm vi WS-4.

## 3. Ma trận trường — `Config` (`DeskAgent.toml`)

Đường dẫn upgrade v1→v2: `Config::load` thấy `config_version < CURRENT` → log cảnh báo → `backup_file_if_needed` tạo `.v1.bak` → bump lên `CURRENT` → `store()`. `Config::store` (config.rs:837) ép `config_version = CURRENT`, tạo `.v1.bak` nếu file trên disk cũ hơn, rồi `store_` tạo `.bak` trước khi ghi.

| Trường | v1 | v2 | Hành vi migrate |
|---|---|---|---|
| `config_version` | `1` | `2` | **ĐỔI**: bump khi load (nếu `< CURRENT`) và luôn ép về `CURRENT` khi ghi. Version **mới hơn** build hiện tại (vd. `3`): **GIỮ nguyên khi đọc** (forward-compatible, không bị hạ cấp), nhưng lần ghi kế tiếp bị **clamp về `CURRENT`** — `.bak` giữ lại nguyên vẹn schema tương lai, kể cả field lạ mà serde bỏ qua |
| `id` (bản "use") | plaintext | bị xóa khi ghi | **ĐỔI**: từ v2 bản ghi luôn ghi `id = ""` ra disk (config.rs:864); định danh sống trong `enc_id` |
| `enc_id` | trống hoặc plaintext | `"00"` + base64(secretbox(id)) | **RE-WRAP**: nếu trống/đổi id → mã hóa lại bằng `encrypt_str_or_original(.., "00")`; nếu đã là `"00"`-ciphertext khớp id hiện tại → **GIỮ nguyên chuỗi cũ** (`keep_encrypted_storage_if_plaintext_unchanged`, config.rs:614) |
| `password` (storage mật khẩu vĩnh viễn) | plaintext | `"01"` + base64(secretbox(`"00"` + base64(h1))) | Xem bảng con dưới |
| `salt` | trống | chuỗi random (`DEFAULT_SALT_LEN`) | **GIỮ**; bắt buộc không trống khi `password` là hashed storage; sync service→user bị từ chối nếu thiếu salt |
| `key_pair` (sk, pk) | Ed25519 | không đổi format | **GIỮ** — sinh đúng một lần (`get_key_pair`), không bao giờ re-wrap |
| `key_confirmed`, `keys_confirmed` | bool / map | không đổi | **GIỮ** |

Bảng con cho `config.password` (các trạng thái storage, tham chiếu `config/permanent_password.rs:9-12`):

| Trạng thái trên disk | Ý nghĩa | Khi `store()` |
|---|---|---|
| plaintext | legacy | **RE-WRAP** → `"00"`-ciphertext (mã hóa đối xứng, `keep_encrypted_storage_if_plaintext_unchanged`) |
| `"00"` + base64(ciphertext) | legacy đã mã hóa (PREFIX `PASSWORD_ENC_VERSION = "00"`) | **GIỮ**: giải mã in-memory để kiểm tra, ghi lại đúng chuỗi cũ nếu plaintext không đổi |
| `"00"` + base64(h1=SHA256(password‖salt)) | hashed legacy (PREFIX `PERMANENT_PASSWORD_HASH_PREFIX = "00"`) | **GIỮ** nguyên verbatim |
| `"01"` + base64(secretbox(`"00"`+base64(h1))) | format hiện tại (PREFIX `PERMANENT_PASSWORD_ENC_VERSION = "01"`) | **GIỮ** nguyên verbatim — không bao giờ decrypt ra disk |

Hai nghĩa của tiền tố `"00"` (ciphertext đối xứng vs. hash h1) được phân biệt khi decode: h1 phải là 32 byte base64 hợp lệ (`decode_permanent_password_h1_from_storage`).

## 3b. Ma trận trường — `Config2` (`DeskAgent2.toml`)

Đường dẫn upgrade tương tự qua `Config2::load` / `Config2::store` (config.rs:533, 570).

| Trường | v1 | v2 | Hành vi migrate |
|---|---|---|---|
| `config_version` | `1` | `2` | **ĐỔI** — cùng quy tắc bump/clamp như `Config` |
| `rendezvous_server` | string | string | **GIỮ** |
| `nat_type`, `serial` | i32 | i32 | **GIỮ** |
| `unlock_pin` | plaintext hoặc `"00"` | `"00"`-ciphertext | **RE-WRAP** khi plaintext (`keep_encrypted_storage_if_plaintext_unchanged`, config.rs:594); đã mã hóa → **GIỮ** |
| `trusted_devices` | JSON | JSON trong `"00"`-ciphertext | **GIỮ**/RE-WRAP khi `set_trusted_devices` ghi lại (config.rs:1751) |
| `socks.password` | plaintext hoặc `"00"` | `"00"`-ciphertext | **RE-WRAP** khi plaintext; đã mã hóa → **GIỮ** (config.rs:584) |
| `options` | map | map | **GIỮ**; chỉ bị lọc bởi `purify_options` (field mặc định/overwrite không lưu lại) |

## 4. `PeerConfig` (`peers/<id>.toml`) — không có `config_version`

Schema `PeerConfig` đóng băng theo nghĩa serde: mọi trường đều có default/deserialize-with nên file cũ cũ bao nhiêu cũng đọc được; field lạ bị serde bỏ qua. Mã hóa tại chỗ: `password` → `encrypt_vec_or_original(.., "00")`, `rdp_password`/`os-username`/`os-password` → `encrypt_str_or_original(.., "00")` (config.rs:1875). Ghi đi qua `store_path` trực tiếp (config.rs:1884) nên **không** hưởng `.bak` của WS-4 — nếu cần backup cho peers thì là work item riêng.

## 5. Kiểm thử

Unit test kèm theo (chạy: `cargo test -p hbb_common config`):

| Test | Chứng minh |
|---|---|
| `config::tests::test_config_v1_upgrade_writes_migration_backup_and_pre_write_bak` | Upgrade v1→v2 tạo **cả hai** backup; `.bak` giữ đúng bytes schema v1 |
| `config::tests::test_config_future_version_reads_forward_and_is_clamped_on_store_with_bak` | Schema tương lai không bị hạ khi đọc; khi ghi bị clamp về `CURRENT`, `.bak` giữ marker tương lai + field lạ |
| `config::tests::test_config2_future_version_reads_forward_and_is_clamped_on_store_with_bak` | Cùng hợp đồng clamp cho `Config2` |
| `config::tests::test_config_migration_preserves_credentials_and_creates_backup` (có sẵn) | Migration giữ nguyên credentials + tạo `.v1.bak` |
| `config::tests::test_config_store_writes_current_version_v2`, `test_config2_store_writes_current_version_v2` (có sẵn) | `store()` luôn ghi ra `CURRENT_CONFIG_VERSION` |

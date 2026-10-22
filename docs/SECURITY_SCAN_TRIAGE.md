# SECURITY SCAN TRIAGE — Mimosa normal-depth (2026-10-22)

Scan: `scan-2026-10-22T14-09-42.780Z-3a5600af4e53` · seal
`sha256:636a2e3988bc70f5d8a32263529367694f82c9e8cc5cae33d4e2e73e8299e639` ·
24 findings, 1188 packages, 9 packages khớp advisory (34 advisory) ·
bound: static_only_no_runtime_execution.

Phân loại theo ranh giới tấn công. Quy tắc: **findings trong công cụ build/CI
chạy offline** (người vận hành đã đứng trên máy) không phải lỗ hổng runtime của
client; vẫn hứa harden khi lần sau đụng tới các script đó.

## 1. Path traversal / command injection — dev tooling (9 HIGH:ACCEPTED)

`scripts/perf-analyze.py:126`, `scripts/measure_remote_perf.py:180`,
`scripts/job.py:97` (không còn tồn tại — check lại), `res/msi/preprocess.py`
(239/280/444/467/509/525), `res/job.py:97`, `build.py:52,184`:

- Toàn bộ là `open(args.out_json, "w")` / subprocess với **đường dẫn do người
  chạy nhập từ CLI**. Kẻ tấn công phải đã có quyền chạy lệnh trên máy thì mới
  khai thác — không vượt được ranh giới đặc quyền nào.
- **Hành động**: ACCEPTED (dev tooling, offline). Hardening khi chạm lại file
  (thêm helper `_resolve_under(base, user_path)` nếu file được tái sử dụng
  trong pipeline tự động có input không tin cậy).

## 2. "Hardcoded credentials" — FIXTURE TEST (6 HIGH:FALSE-POSITIVE)

`libs/hbb_common/src/config.rs:3117,3251,3267`,
`libs/hbb_common/src/config/permanent_password.rs:219`,
`scripts/matrix-verify.py:109,116`:

- Toàn bộ nằm trong `#[test]` (mật khẩu mẫu "p@ssw0rd", "legacy-secret",
  "01legacy-secret") — fixture kiểm thử, không phải credential thật.
- **Hành động**: FALSE-POSITIVE, không đổi.

## 3. Taint medium (2 MEDIUM:ACCEPTED)

`libs/base/src/platform/macos.rs:35`, `src/platform/linux.rs:912` —污点 cross-file
trên platform KHÔNG thuộc phạm vi GA của DeskAgent (macOS waived v1.5, Linux
chưa ship). Ghi nhận, xem lại khi build những nền tảng đó.

## 4. Advisory packages (offline match: 9 packages / 34 advisory)

Danh sách gói khớp nằm trong `dependent…/findings.json` của scan. Đây là các
crate cũ theo lockfile (Nguồn: Cargo.lock ghim phiên bản RustDesk upstream).
**Không update blanket** — mọi nâng crate phải qua gate build
(`--locked`, desktop + manager) vì đã từng vỡ (bài học transitive). Xử lý theo
lô khi có sprint riêng.

## 5. Điều đã làm song song và KHÔNG thuộc scan này

- `WS_EX_NOACTIVATE` + style strip dùng FFI — đã test bằng tay trên máy thật.
- Không có credential mới nào được nhập vào nguồn (ràng buộc hook Mimosa).

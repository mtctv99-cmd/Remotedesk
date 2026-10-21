# DeskAgent Security Downgrade Policy (WS-7)

**Tài liệu:** Chính sách chấp nhận version cũ (có ngày tắt) và cơ chế từ chối downgrade
**Trạng thái:** ACTIVE — phần floor v2 đã được enforce bằng unit test; phần lịch tắt v1 gắn với mốc 2.0 GA
**Tài liệu liên quan:** `docs/PROTOCOL_V2_SPEC.md` (§2 ALPN, §6 handshake, §8 sunset plan), `docs/STORAGE_MIGRATION_MATRIX.md`

---

## 1. Bảng đăng ký version (version registry)

| Lớp | Version | Nơi định nghĩa | Trạng thái chấp nhận |
|---|---|---|---|
| KX scheme gốc (1 key hai chiều) | `0` | ngầm định (field trống) | Chấp nhận **chỉ trên wire v1**; bị từ chối trên session v2 |
| KX scheme v1 (split-key + transcript) | `1` | `hbb_common::tcp::KX_VERSION_LATEST = 1` (`tcp.rs:31`) | Chấp nhận **chỉ trên wire v1**; bị từ chối trên session v2 |
| KX scheme v2 | `2` | `crate::rendezvous_mediator::v2::KX_VERSION_LATEST = 2` (`rendezvous_mediator.rs:1435`) | **Floor của session v2** — mọi session v2 chạy ≥ 2 |
| Wire signaling v1 | `rendezvous.proto`, package `hbb`, không ALPN | `libs/hbb_common/protos/rendezvous.proto` | Chấp nhận đến ngày tắt (mục 3) |
| Wire signaling v2 | `deskagent_v2.proto`, package `deskagent.v2`, ALPN `deskagent-sig/2` | `libs/hbb_common/protos/deskagent_v2.proto` | Generation mới — không bao giờ tự hạ xuống v1 |
| Schema storage config | `config_version` 1→2 | `libs/hbb_common/src/config.rs:55-57` | Upgrade tự động có backup; schema tương lai đọc xuôi, clamp khi ghi (xem matrix) |

## 2. Cơ chế chống downgrade (đã enforce trong code)

### 2.1 Floor của session v2

`v2::KX_VERSION_MIN = KX_VERSION_LATEST = 2` (`rendezvous_mediator.rs:1439`): một session đã đi qua lớp v2 **không được đàm phán xuống dưới floor**. Hàm `v2::negotiate_kx_version` (`rendezvous_mediator.rs:1464`):

- peer offer `< KX_VERSION_MIN` (vd. `1` hoặc `0`) → trả `Err(DowngradeRejected { offered, floor })` — **từ chối thẳng**, không bao giờ im lặng hạ cấp;
- peer offer `≥ KX_VERSION_LATEST` → lấy `min(advertised, KX_VERSION_LATEST)` — version mới hơn build hiện tại bị **cap** (chấp nhận hướng lên là hướng tương thích; chạy scheme chưa build là không thể).

Enforcement test: `rendezvous_mediator::tests::v2_kx_negotiation_refuses_the_downgrade_below_the_floor` (`rendezvous_mediator.rs:2311`).

> Phân biệt với v1: trên wire v1, `hbb_common::tcp::kx_version_for` (`tcp.rs:40`) vẫn lấy `min(advertised, 1)` như cũ — chính sách này **không đổi hành vi v1**.

### 2.2 Tách miền xác thực (separate authentication domain)

- v1 ký KxParams trong miền `hbb_common::tcp::KX_PARAMS_DOMAIN = b"rdkx-params"` (`tcp.rs:35`).
- v2 ký trong miền riêng `v2::AUTH_DOMAIN = b"deskagent-sig/2/kx-params"` (`rendezvous_mediator.rs:1448`) — tên miền chứa đúng ALPN token của generation.

Hệ quả: chữ ký/transcript tạo cho một generation **không bao giờ verify ở generation kia** — chặn cross-generation replay (một MITM dùng chữ ký v1 để "xác thực" session v2 hoặc ngược lại). Enforce test: `rendezvous_mediator::tests::v2_auth_domain_is_separate_from_the_v1_domain` (`rendezvous_mediator.rs:2342`).

### 2.3 Gắn generation vào transport

- ALPN `deskagent-sig/2` ghép cặp 1-1 với schema `deskagent.v2` (điều khoản versioning #5 trong `deskagent_v2.proto`): token và package version di chuyển cùng nhau.
- Backend signaling tự khai báo generation qua `Signaling::signaling_transport()` (`rendezvous_mediator.rs:1362`): `"rendezvous-v1"` hôm nay, `"deskagent-sig/2"` khi backend v2 vào. Test: `signaling_defaults_point_at_the_v1_wire` — backend v1 không được lặng lẽ biến thành v2.
- Các operation chỉ có trên v2 (`relay-select`, `session-negotiate`) phải **từ chối rõ ràng** trên backend v1, không giả vờ chạy: `v2_only_signaling_ops_decline_on_the_v1_backend` (`rendezvous_mediator.rs:2273`).

### 2.4 Downgrade phía lưu trữ

Schema config tương lai (version cao hơn build) không bị hạ cấp khi đọc, nhưng bị clamp về `CURRENT_CONFIG_VERSION` khi ghi — bản gốc (kể cả field lạ) được giữ trong `.bak` trước ghi. Chi tiết và test: `docs/STORAGE_MIGRATION_MATRIX.md` §3, §5.

## 3. Chính sách chấp nhận version cũ — có ngày tắt (sunset)

Nguyên tắc: **chấp nhận cũ là trạng thái chuyển tiếp có giới hạn thời gian, không phải cam kết vĩnh viễn.**

1. **Hiện tại (dual-stack, PROTOCOL_V2_SPEC §8.1):** client nói được cả hai generation. Wire v1 (port 21116–21119, `rendezvous.proto`) vẫn được chấp nhận đầy đủ — mediator mặc định chạy backend v1 qua seam `Signaling`; không hành vi nào thay đổi bởi chính sách này.
2. **Session v2 không nằm trong giai đoạn chuyển tiếp:** từ thời điểm một endpoint tham gia một session v2, floor `KX_VERSION_MIN = 2` có hiệu lực tức thì — không có "cho phép v1 thêm một thời gian" trong phiên. Việc chấp nhận version cũ chỉ áp dụng cho việc **khởi tạo kết nối bằng wire v1**, không áp dụng cho phiên v2.
3. **Ngày tắt (sunset) của wire v1:** được chốt tại mốc phát hành 2.0 GA và ghi đè trực tiếp vào mục này (ngày hiện tại: **chưa chốt — quyết định của release 2.0 GA**; tài liệu này là nguồn sự thật duy nhất cho mốc thời gian). Sau ngày tắt:
   - v2 endpoint từ chối mọi kết nối chỉ offer wire v1 / KX ≤ 1 với `STATUS_VERSION_REJECTED` (message v2, `deskagent_v2.proto`), log rõ lý do;
   - không có fallback âm thầm sang v1 dưới bất kỳ hình thức nào.
4. **Quy tắc hạ floor:** `KX_VERSION_MIN` chỉ được giảm qua quyết định bảo mật tách biệt (security review), không bao giờ là side-effect của một PR tính năng.
5. **Phát hiện & phản ứng khi bị ép hạ cấp:** mỗi lần từ chối downgrade là một `Err`/`STATUS_VERSION_REJECTED` có log — phía vận hành phải nhìn thấy được tỉ lệ từ chối; nếu một peer "hợp lệ" đột nhiên chỉ offer version cũ, đó là tín hiệu MITM/rollback và phải được điều tra, không được tự động hạ cấp theo.

## 4. Tóm tắt kiểm thử

| Test (lệnh: `cargo test -p deskagent --lib rendezvous_mediator`) | Chính sách được enforce |
|---|---|
| `v2_kx_negotiation_refuses_the_downgrade_below_the_floor` | §2.1 — floor v2, từ chối `1`/`0`, cap version tương lai |
| `v2_auth_domain_is_separate_from_the_v1_domain` | §2.2 — miền xác thực v2 ≠ `rdkx-params` |
| `signaling_defaults_point_at_the_v1_wire` | §2.3 — backend mặc định vẫn là v1, không lặng lẽ đổi generation |
| `v2_only_signaling_ops_decline_on_the_v1_backend` | §2.3 — op v2 không chạy giả trên v1 |

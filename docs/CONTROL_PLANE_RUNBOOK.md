# Control Plane Runbook — DeskAgent owned signaling/relay/enrollment (WS-6)

> Trạng thái: signaling + blind relay + enrollment API đã chạy (dual-stack cùng
> hbbs/hbbr per PROTOCOL_V2_SPEC.md §8). E2E session qua v2 data channel
> (QUIC P2P + Noise data-plane) là follow-up — client hiện tại vẫn session qua
> v1/hbbs; không claim điều ngược lại.

## 1. Kiến trúc

```text
deskagent-control (image deskagent-control-plane:latest)
 ├─ signaling  TCP 34116  deskagent-sig/2  (hello/register/heartbeat/punch/relay_select/signal)
 ├─ relay      TCP 34117  deskagent-relay/2 (§7 blind envelope: magic DA 02, route by session UUID)
 └─ enroll API HTTP 127.0.0.1:34118 (loopback; SSH-tunnel để mint invite)
         ↕ shared SQLite: ./manager-data/manager.db (WAL, short transactions)
deskagent-manager (:8080) — console/admin/API/AI, KHÔNG đổi
hbbs/hbbr (21115-21119) — v1 fleet, KHÔNG đổi trong dual-stack
```

## 2. Ports / firewall

| Port | Service | Mở cho ai |
|---|---|---|
| 34116/tcp | signaling | LAN clients (v2) |
| 34117/tcp | blind relay | LAN clients (v2) |
| 34118/tcp | enroll API | CHỈ host loopback (`127.0.0.1:34118:34118`) — admin SSH-tunnel |
| 8080/tcp | manager | LAN/VPN (HTTP thuần — sau reverse-proxy TLS ở production) |
| 21115-21119 | hbbs/hbbr | giữ nguyên cho v1-compat (quyết ports: GIỮ số cũ cho v1, v2 dùng 3411x riêng) |

## 3. Env (bảng duy nhất đáng tin)

| Var | Đặt ở | Bắt buộc? | Ghi chú |
|---|---|---|---|
| DESKAGENT_ADMIN_USER/PASS | manager | MỚI: bắt buộc (fail-closed cả weak). CŨ (VM hiện tại): giữ nguyên compose, KHÔNG xoay khi chưa có kế hoạch | pass yếu (`admin`/`<8`) = panic lúc boot |
| DESKAGENT_SERVER_PRIVKEY | manager | MỚI: bắt buộc. CŨ: để trống để seed file `manager-data/manager_privkey.seed` thắng (continuity) | Đổi giá trị = đổi trust anchor deploy + server_key → client cũ từ chối job |
| DESKAGENT_CONTROL_DB | control | `/shared/manager.db` trong compose | cùng file với manager |
| DESKAGENT_CONTROL_RELAY/SIG_ADVERTISE | control | bắt buộc đúng IP public (`<DOCKER-HOST-IP>:3411x`) | sai = client punch/relay vào IP container 172.x (lỗi y hệt hbbs thiếu `-r`) |
| DESKAGENT_CONTROL_BIND_* | control | sig/relay mặc định 0.0.0.0; API mặc định 127.0.0.1:34118, nhưng trong Docker đặt 0.0.0.0:34118 (app bind loopback *trong container* thì publish không tới được — biên bảo vệ thật là phía host `127.0.0.1:34118:34118` ở ports) |

## 4. Key ceremony (thay flow paste `id_ed25519.pub` thủ công)

1. Admin đăng nhập manager console (`:8080`) → Bearer admin token (TTL 7 ngày).
2. `POST 127.0.0.1:34118/api/enroll/invite` (header `Authorization: Bearer <admin>`)
   → `{invite (64 hex, hiện 1 lần), expires_in: 86400}`.
3. Trên máy fresh: `deskagent --v2-enroll <http://host:34118> <invite>`
   → client POST claim → nhận `{device_token, server_key, signaling, relay}`,
   lưu local + IN fingerprint SHA-256 của `server_key` ra màn hình để admin
   đối chiếu (TOFU có xác minh, xem runbook §6).
4. Invite single-use + TTL 24h; claim sai/khác → 401 không phân biệt lý do.
5. Từ đây device dùng `X-Device-Token` với manager như device register thường.

## 5. Redeploy (VM 192.168.232.129, ~/deskagent/deploy)

```bash
# 0. Backup compose + tag image đang chạy
cp docker-compose.yml docker-compose.yml.bak-$(date +%Y%m%d)
docker tag deskagent-manager:latest deskagent-manager:backup-$(date +%Y%m%d-%H%M%S)
# 1. Đồng bộ source (local): tar --exclude=target --exclude=.mimosa --exclude=.zcode
#    manager/ + control-plane/ -> ~/deskagent/
# 2. Build + up (hbbs/hbbr KHÔNG đụng):
docker compose build manager deskagent-control
docker compose up -d manager deskagent-control
# 3. Smoke (từ VM hoặc SSH-tunnel):
#    - signaling: hello version 2 -> negotiated_version 2; version 1 -> status 4
#    - relay: 2 socket cùng session UUID forward nguyên bytes
#    - enroll: claim sai -> 401; invite (admin) -> claim -> device_token + server_key
#    - manager: /api/discover vẫn 200; console login OK
# 4. Rollback: docker compose down deskagent-control (v1 fleet không ảnh hưởng);
#    manager: docker tag <backup> :latest && up -d (volume giữ nguyên)
```

Continuity rules (không thương lượng):
- KHÔNG set DESKAGENT_SERVER_PRIVKEY khác seed hiện có trên volume đang chạy.
- KHÔNG xóa/rebuild volume manager-data/hbbs-data.
- KHÔNG commit secret vào repo (compose repo chỉ giữ placeholder).

## 6. TOFU fingerprint (xác minh trust anchor khi enroll)

`server_key` là base64 Ed25519 pubkey. Fingerprint hiển thị = `SHA256:<base64(sha256(raw_pubkey))>`.
Admin đối chiếu với giá trị manager đã publish (console /settings hoặc
`SELECT value FROM settings WHERE key='server_key'` trên BẢN COPY db, không
query prod trực tiếp khi không cần). Khớp mới duyệt device vào fleet.

## 7. Giới hạn đã biết (trung thực)

- Data channel v2 (QUIC P2P E2EE + BBR + Noise data-plane §5-6 spec) CHƯA có;
  relay hiện forward TCP opaque (đúng §7 envelope), P2P punch coordination đầy
  đủ (STUN probes/quic handshake) là follow-up sau client v2 transport.
- Signaling transport binding hiện tại là JSON length-prefix (documented);
  protobuf codegen từ `deskagent_v2.proto` là follow-up không đổi semantics.
- Enroll claim có in-memory per-IP failure counter: 10 lỗi trong 5 phút trả 429. Counter mất khi process restart và dùng socket peer IP; nếu reverse proxy che IP, limiter không phân biệt client. Test helper threshold có; kiểm thử qua proxy/LAN và limiter phân tán chưa làm. Giữ enroll chỉ qua host-loopback/SSH tunnel cho tới khi xác minh.
- Mọi metric E2E v2: NOT MEASURED (chưa có traffic v2 thật).

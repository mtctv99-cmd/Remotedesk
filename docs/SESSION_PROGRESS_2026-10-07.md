# Session progress 2026-10-07 — WS-1 finish, WS-6 control plane live, perf Phase 02

> Scope respected: no `flutter/lib`, `flutter/test`, `pubspec` writes; Rust
> backend + build + docs + manager/control-plane only. Toolchain untouched
> (Rust 1.75). No version bumps. AGPL attribution kept.

## 1. Shipped this session

### WS-1 finish — last 6 rustdesk-org crates vendored (10 packages, 5 repos)
- `vendor/{fuser,hwcodec,nokhwa,tfc,webm}` copied byte-for-byte from the pinned
  cargo git checkouts; `libs/scrap` (webm/hwcodec/nokhwa), `libs/clipboard`
  (fuser), `libs/enigo` (tfc) switched to path deps, versions unchanged
  (0.16.0/0.7.1/0.10.7/0.7.0/1.1.0+1.0.4).
- `Cargo.lock`: **0 `rustdesk` source URLs** (verified by scan). Only remaining
  manifest URL is enigo's `rdev` git string, redirected by the pre-existing
  `[patch.rdev]` to `vendor/rdev` (never fetched).
- Gate: `cargo check --locked --lib --features flutter` pass.
- `docs/OWNERSHIP.md`: 5 repos moved from "deliberately left" to vendored tables.

### WS-6 — owned control plane live on the VM (dual-stack, hbbs/hbbr untouched)
- New crate `control-plane/` (standalone workspace, pinned deps, own lock):
  signaling TCP 34116 (`deskagent-sig/2` JSON binding of the §3 IDL: hello/
  register/heartbeat/punch/relay_select/signal-forward, Ed25519 PeerId verify
  over `AUTH_DOMAIN`, KX floor 2, v1 hello → VERSION_REJECTED), blind relay
  TCP 34117 (§7 envelope: magic DA 02, route-by-session-UUID, opaque forward,
  hijack-reject, idle reap), enroll API (loopback HTTP: admin-invite →
  single-use claim → device token + server_key anchor + addrs; shares
  manager.db + admin/device-token schemes, WAL + busy_timeout).
- 8 unit tests pass; live smoke on 192.168.232.129: v2 hello ok / v1 refused /
  relay pair forwards bytes / enroll fail-closed (401s) / full positive flow
  (admin login → invite → claim → token valid on manager → smoke client
  deleted, prod clean).
- `deploy/docker-compose.yml` (+ VM copy): `deskagent-control` service
  (34116/34117, loopback-published 34118, shared `./manager-data:/shared`);
  manager env guidance comments (no secret rotation on the live volume).
- `manager` image rebuilt from current source and redeployed (was 31h stale);
  `manager_privkey.seed` continuity kept (no env override on live volume).
- `docs/CONTROL_PLANE_RUNBOOK.md`: ports/firewall, env table, key ceremony,
  redeploy + rollback, TOFU fingerprint, honest limits (§7: no v2 data channel
  yet, JSON binding now / proto codegen later, metrics NOT MEASURED).
- Fixed along the way (smoke-found): enroll API needs `0.0.0.0` bind inside
  the container (loopback-in-container never receives published traffic);
  boundary stays host-side `127.0.0.1:34118`.

### Client key ceremony — `deskagent --v2-enroll <api-base> <invite>`
- `src/deskagent/enroll.rs`: blocking claim (ureq, established pattern),
  stages `v2-{device-token,server-key,signaling,relay,peer-id}` as LOCAL
  options (explicitly NOT on the manager-sync allowlist — same reason "key"
  is excluded), prints `SHA256:` TOFU fingerprint, refuses id mismatch,
  exits nonzero on failure. 3 unit tests pass. Full lib suite: 373 passed,
  0 failed. Dual-stack: v1 id/servers keep serving; activation is follow-up.

### Perf — probes + Phase 02 (audit PB-01/PB-02)
- `src/perf_probe.rs`: T1–T7 `log::trace!` markers (target `deskagent_perf`,
  zero-cost when trace off); hooks at send_mouse/send_key_event (T1),
  handle_mouse/Key arms (T2), capture Ok (T3), encode Ok (T4), VideoFrame
  arrival (T5), decode Ok (T6), on_rgba/on_texture (T7). T0 stays Dart-side
  (other session). Join-by-id needs wire ids = v2-data-channel follow-up.
- Phase 02: `SEND_TIMEOUT_VIDEO` 12_000→300ms (connection.rs:505, OTHER scales
  x10), `VIDEO_QUEUE_SIZE` 120→3 (client.rs:111), drain-to-latest in
  `start_video_thread` (drop counting via trace). Rollback = revert constants.
- Gate + full suite green (373 passed). All Phase-02 gains: NOT MEASURED
  (bench harness is the next step per PERFORMANCE_BENCHMARK_PLAN).

### Follow-up session (same day) — handshake core, version feed, analyzer, CI doc
- `libs/base/src/kx_v2.rs` (owned seam, zero new deps — sodiumoxide via
  hbb_common): Noise_IK per spec §6 (es/ss/ee/se transcript, HKDF-SHA256
  RFC 5869 hand-rolled + .NET-oracle KAT, ChaCha20-Poly1305-IETF transport,
  version-bind before Split, v1-domain separation). 8/8 tests (roundtrip both
  directions, tamper→fail, peer-mismatch, floor, binding, x25519-bind helper
  for enrollment). Two real bugs found+fixed en route (Ed-seed-as-X25519
  asymmetry → independent X25519 static keys; responder's 4th DH must be
  DH(eB,sA) not DH(sB,eA) repeat). NOT wired into any session yet — transport
  integration is the next step; base suite 24/24 green.
- Version feed: control-plane `GET /api/version` (public, settings-backed,
  404 when unpublished — proven live on VM) + client opt-in `v2-update-feed`
  in `check_software_update()` (SSRF-guarded, notification-only, same flutter
  event contract; hash-enforced auto-install = follow-up). 1 new test.
  Full lib suite now 374 passed / 0 failed.
- `scripts/perf-analyze.py` (stdlib-only, `--selftest` green): trace markers
  → per-stage count/rate + gap p50/p95/p99/max + CSV. Deliberately no E2E
  column (would be fabricated without wire ids).
- `docs/CI_PROVENANCE.md`: full rustdesk* inventory of workflows/build
  (fetches, actions, names) with re-host/replace order — no blind edits.
- Score unchanged at 48/100 (handshake unwired, feed notification-only);
  the table in §2 below still holds.

### Cleanup
- `.github/workflows/fdroid.yml` → `.disabled` (polled upstream releases;
  repointing would invent URLs). Logged in LEGACY_CLEANUP_LOG §4.
- Ports decision logged (2111x v1-compat, 3411x v2).
- `docs/INSTALL_UPGRADE_MATRIX.md`: matrix designed, all boxes NOT TESTED
  (needs signed artifacts + clean VMs).

## 2. Strict-DoD score: 38 → 48/100 (my reading, evidence above)

| Dimension | Now | Why (strict) |
|---|---|---|
| Build | 6 | Rust manifests+lock: 0 fetched rustdesk URLs. Left: 8 Flutter forks (WS-8), CI actions/engine/drivers, SBOM, rdev URL string |
| Runtime | 1 | Sessions still require hbbs/hbbr binaries |
| Protocol | 3 | v2 signaling live+tested server-side; clients still v1; data channel pending |
| Server | 4 | Owned sig+relay+enroll deployed+proven; hbbs still serves sessions |
| Security | 4 | v2 KX floor + domain separation + downgrade tests + enroll anchor flow; Noise data-plane pending |
| Storage | 5 | config_version v1/v2 + backup + matrix (prior session; untouched today) |
| UI | 2 | untouched (parallel session owns WS-8) |
| Branding | 8 | unchanged today (fdroid workflow disabled, not deleted) |
| Source-code | 6 | +owned control-plane; submodule detached earlier; Flutter fork code remains |
| Deployment | 4 | manager rebuilt fresh + control service deployed; installers/CI provenance unchanged |
| **Total** | **48** | NOT INDEPENDENT → still NOT INDEPENDENT (need ≥85), but Build/Server/Protocol unblocked |

## 3. Deliberately NOT done (follow-ups, no overclaim)

1. v2 data channel (QUIC P2P E2EE, BBR, Noise data-plane) + client mediator
   cutover — the actual session migration (WS-6 remainder).
2. WS-8: Sciter removal + 8 Flutter forks (parallel session).
3. CI provenance (actions/engine/drivers), SBOM regeneration, version-check
   feed migration, `tools/server` removal (needs #1 + install matrix green).
4. Bench harness runs (T0–T7 join, stress matrix, OCR) — probes are in,
   numbers are NOT MEASURED.
5. `cargo test --lib` full-suite note: green today (373 pass); the earlier
   E0425 scare was my own `len("SHA256:")` typo in a new test, fixed —
   `video_qos` tree was never broken.

## 4. Rollback map

- Control plane: `docker compose down deskagent-control` (v1 fleet unaffected).
- Manager: `backup-*` image tags on VM + untouched volumes.
- Perf Phase 02: revert 3 constants/1 loop (all marked with audit PB refs).
- Enroll CLI: additive only (`--v2-enroll` branch + new module).
- fdroid: rename `.disabled` back.

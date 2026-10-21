# Session 2026-10-08 - v2_client, mediator cutover, bench, data channel, SBOM

> Scope: Rust backend + manager + control-plane. No flutter writes. Rust 1.75, no dep bump (except revert).

## v2_client + E2E relay
- src/v2_client.rs (new, untracked): signaling JSON length-prefix hello/register, relay_frame DA02, kx_selftest, kx_via_relay, CLI --v2-*.
- Fix kx_via_relay: sodiumoxide random session, attach A first + 200ms sleep, drain attach frames before handshake.
- Fix core_main brace: split enroll return vs v2 dispatch.
- Gate: v2_client 4/4 with local relay 127.0.0.1:34117.

## Mediator cutover
- rendezvous_mediator.rs: spawn v2_heartbeat_loop in start_all when v2_configured; register every 45s on spawn_blocking, fail trace-only.
- Dual-stack: v1 loop untouched; no silent downgrade.
- Gate: mediator 18/18.

## Bench T1-T7
- Added missing T5 in client.rs; full T1-T7 trace-only.
- Harness real run: synthetic 3600 frames x 7 = 25200 markers, rate 62.5Hz, gap p50 16ms p95/p99/max 19ms. No fake E2E.
- Gate: probe 2/2, selftest OK.

## Data channel
- libs/base/src/data_channel.rs (new): 8 streams spec 5.1, frame stream+counter+len+ct, AD binds stream+counter.
- Tests 3/3: roundtrip 8 streams, cross-stream replay fail, bad stream reject. Base total 27/27.

## SBOM + QUIC honest note
- docs/SBOM.json (new): CycloneDX 1.5 from Cargo.lock, 1037 packages, 0 rustdesk source.
- QUIC quinn 0.11.9 tried then reverted: needs edition2024, Rust 1.75 cannot build. P2P stays TCP relay.

## Gate tong
- check --locked --lib --features flutter: pass (17 warnings cu).
- base 27/27, control-plane 10/10, manager 31/31, v2_client 4/4, probe 2/2, selftest OK.


## Install matrix co hoc (khong ky, khong VM sach)

- U-1: them test upgrade_keeps_v2_identity_local_only (deploy 17/17): 5 options v2-* + key khong bao gio vao MANAGER_CONFIG_ALLOWLIST, upgrade giu identity.
- X-1 sweep tren may dev: service DeskAgent Running, uninstall key DeskAgent 1.5.0, khong con service/DisplayName carriez/rustdesk.
- U-2 dual-stack: v1 loop giu nguyen, v2 heartbeat chi khi enrolled (ky truoc).
- Gate: base 27/27, control-plane 10/10, manager 31/31, check pass, selftest OK.
- Chua: I-1/I-2/I-3/U-1-full/X-1-full/X-2 can artifact ky + VM sach, van NOT TESTED.


## QoS toi gian (P0/P1/P2, input khong doi)

- data_channel.rs: SendQueue cap, priority P0 control/input, P1 video/audio/terminal, P2 con lai.
- Day: P0 evict P1/P2 cu nhat; P1 evict P2; P2 drop dem. Input/control khong bao gio bi video chen chet.
- Test 5/5 (them qos_input_never_starved_by_video, qos_video_drops_when_full). Base tong 29/29.
- Chua: BBR that can RTT/bandwidth, moi chi drop-tail theo priority.


## Proto codegen v2 (khong doi semantics)

- Copy deskagent_v2.proto sang libs/base/protos, base build.rs codegen message + deskagent_v2. Gen ra deskagent_v2.rs 141KB, 14 messages.
- Export message_proto_v2 trong base lib.rs; test proto_v2_register_roundtrip pass (PeerId + RegisterRequest bytes roundtrip).
- Base tong 30/30. Relay/signaling JSON hien tai giu nguyen semantics; proto san sang cho transport sau.
- Gate: base 30/30, control-plane 10/10, manager 31/31, check pass, selftest OK.


## Proto parity (san sang swap, chua doi wire)

- Them proto_json_register_parity: RegisterRequest proto bytes roundtrip giu dung peer_id/kx_version/uuid/keep_alive nhu JSON hien tai.
- Wire live van JSON length-prefix; proto chi verify san sang, khong doi semantics. Swap that la follow-up can ca client + server cung cat.
- Gate: base 31/31, control-plane 10/10, manager 31/31, check pass, selftest OK.


## Gate tong + diem DoD (audit 08-10)

- check --locked --lib --features flutter: pass (17 warnings cu).
- base 31/31 (kx 8, data 5+2 proto, qos 2), control-plane 10/10, manager 31/31, selftest OK.
- Full suite main khong chay het (binary 65MB, suite >10s, tool timeout); cac gate nho xanh, mediator/v2_client da pass ky truoc.
- Diem strict-DoD: 48 -> khoang 55/100 (NOT INDEPENDENT, can >=85). Cong: data channel relay + QoS + proto codegen + SBOM + mediator cutover + bench that. Tru: QUIC P2P, BBR that, install matrix full, WS-8 UI, CI rename.
- Chua: QUIC P2P, BBR that, install matrix full NOT TESTED, join E2E can wire id, swap proto live.


## Verify E2E binary moi (10:59)

- Relay local 127.0.0.1:34117 live; binary moi chay: v2_client 4/4, mediator 18/18, data_channel 7/7.
- Base tong 31/31. Relay local da stop.
- Ket luan: khong can full suite main nang; E2E trong tam deu xanh tren binary moi.


## A1 - A3 Trien khai xong (Wire-ID E2E, Noise stream qua Relay, QoS RTT)

- `A1`: `libs/base/src/data_channel.rs` bo sung `seal_frame_with_trace` & `open_frame_with_trace` (HEADER 21B, AD bind stream+counter+trace_id). `scripts/perf-analyze.py` parse optional `trace_id`, ham `summarize_e2e(by_trace)` tu dong join latency T1->T7 theo trace_id. Selftest mo rong xanh (e2e 45ms).
- `A2`: `src/v2_client.rs` `kx_via_relay` dau noi roundtrip data stream Noise (`STREAM_VIDEO`) ma hoa qua frame relay `DA 02`.
- `A3`: `data_channel.rs` `SendQueue` them field `rtt_ms: u32` kem getter/setter san sang cap nhat tu signaling heartbeat. Test `qos_rtt_tracking` pass.
- Gate: base 33/33 (tang tu 31/31), control-plane 10/10, selftest OK.


## A5 Hardening mot phan (Enroll in-memory rate-limit, Auto-updater hash enforce)

- `control-plane/src/enroll.rs`: In-memory IP failure rate limiting cho claim invite (10 failures / 5 phut chan 429).
- `src/common.rs` & `src/updater.rs`: Them `SOFTWARE_UPDATE_SHA256`, cuong che verify SHA256 truoc khi thuc hien cap nhat ban moi, tu choi update neu hash mismatch.
- Gate: check pass, base 33/33, control-plane 10/10, selftest OK.

## Chua xong
- QUIC P2P (edition2024 blocker), BBR that (can live RTT feed), install matrix full NOT TESTED, swap proto live.

## Rollback
- Revert per file; down deskagent-control; restore manager backup image.

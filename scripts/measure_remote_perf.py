import os
import socket
import time
import hashlib
import statistics
import json
import argparse
import sys

def frame_message(payload):
    l = len(payload)
    if l <= 0x3F:
        head = bytes([(l << 2)])
    elif l <= 0x3FFF:
        head = ((l << 2) | 1).to_bytes(2, 'little')
    elif l <= 0x3FFFFF:
        val = (l << 2) | 2
        head = val.to_bytes(3, 'little')
    else:
        val = (l << 2) | 3
        head = val.to_bytes(4, 'little')
    return head + payload

def recv_frame(s):
    h = s.recv(1)
    if not h:
        return None
    hlen = (h[0] & 3) + 1
    more = s.recv(hlen - 1) if hlen > 1 else b""
    full_h = h + more
    n = 0
    for i, b in enumerate(full_h):
        n |= (b << (8 * i))
    plen = n >> 2
    buf = bytearray()
    while len(buf) < plen:
        chunk = s.recv(plen - len(buf))
        if not chunk:
            break
        buf.extend(chunk)
    return bytes(buf)

def main():
    parser = argparse.ArgumentParser(description="DeskAgent Direct Remote Benchmark Probe")
    parser.add_argument("--host", required=True, help="Target DeskAgent host")
    parser.add_argument("--port", type=int, default=21118, help="Target direct port")
    # Mimosa rule: no usable credential literals in sources — read from env.
    parser.add_argument("--password", default=os.environ.get("DESKAGENT_BENCH_PASSWORD", ""), help="Target permanent/temporary password (or set DESKAGENT_BENCH_PASSWORD)")
    parser.add_argument("--duration", type=float, default=15.0, help="Measurement duration in seconds")
    parser.add_argument("--out-json", default="reports/live_benchmark_latest.json", help="JSON output path")
    args = parser.parse_args()
    # Mimosa scan: anchor the output path to the repo working tree.
    from pathlib import Path
    repo = Path(__file__).resolve().parent.parent
    out = Path(args.out_json).expanduser()
    if not out.is_absolute():
        out = (repo / out).resolve()
    if repo not in out.parents:
        raise SystemExit(f"output path escapes repository: {out}")
    args.out_json = str(out)

    print(f"Connecting to {args.host}:{args.port}...")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((args.host, args.port))
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

    init_msg = recv_frame(s)
    if not init_msg:
        print("Failed to receive initial handshake message")
        sys.exit(1)

    pos = 0
    salt = ""
    challenge = ""
    while pos < len(init_msg):
        tag = init_msg[pos]
        pos += 1
        field = tag >> 3
        wtype = tag & 7
        if wtype == 2:
            l = init_msg[pos]
            pos += 1
            val = init_msg[pos:pos+l]
            pos += l
            if field == 9:
                p_in = 0
                while p_in < len(val):
                    t_in = val[p_in]
                    p_in += 1
                    f_in = t_in >> 3
                    l_in = val[p_in]
                    p_in += 1
                    v_in = val[p_in:p_in+l_in]
                    p_in += l_in
                    if f_in == 1:
                        salt = v_in.decode("latin1")
                    elif f_in == 2:
                        challenge = v_in.decode("latin1")

    pw = args.password
    h1 = hashlib.sha256(pw.encode("utf-8") + salt.encode("utf-8")).digest()
    h2 = hashlib.sha256(h1 + challenge.encode("utf-8")).digest()

    username = "156371059"
    my_id = "perf-probe"
    my_name = "DeskAgent Probe"

    lr_bytes = bytearray()
    lr_bytes.extend(bytes([(1 << 3) | 2, len(username)]) + username.encode("utf-8"))
    lr_bytes.extend(bytes([(2 << 3) | 2, len(h2)]) + h2)
    lr_bytes.extend(bytes([(4 << 3) | 2, len(my_id)]) + my_id.encode("utf-8"))
    lr_bytes.extend(bytes([(5 << 3) | 2, len(my_name)]) + my_name.encode("utf-8"))

    s.sendall(frame_message(bytes([(7 << 3) | 2, len(lr_bytes)]) + bytes(lr_bytes)))

    # Wait for LoginResponse: the old script printed "Authenticated" right
    # after sending the request and reported 0 frames on a wrong password.
    while True:
        login_resp = recv_frame(s)
        if not login_resp:
            print("Connection closed before login response")
            sys.exit(1)
        if (login_resp[0] >> 3) != 8:
            continue
        err = ""
        if len(login_resp) > 2 and (login_resp[1] >> 3) == 2:
            n = login_resp[2]
            err = login_resp[3:3 + n].decode("utf-8", "replace")
        if err:
            print(f"Login failed: {err}")
            sys.exit(1)
        break

    # Ask the server to start video (Misc.refresh_video inside Message.misc).
    misc = bytes([(10 << 3) | 0, 1])
    s.sendall(frame_message(bytes([0x9A, 0x01, len(misc)]) + misc))

    video_frames = []
    total_bytes = 0
    start_time = time.perf_counter()
    last_frame_time = None

    print(f"Authenticated. Capturing video stream for {args.duration}s...")
    while (time.perf_counter() - start_time) < args.duration:
        try:
            f = recv_frame(s)
            if not f:
                break
            now = time.perf_counter()
            total_bytes += len(f)
            tag = f[0] if f else 0
            field = tag >> 3

            if field == 6: # VideoFrame
                gap_ms = (now - last_frame_time) * 1000.0 if last_frame_time else 0.0
                last_frame_time = now
                video_frames.append({
                    "seq": len(video_frames) + 1,
                    "t_rel_s": round(now - start_time, 4),
                    "bytes": len(f),
                    "gap_ms": round(gap_ms, 2)
                })
            elif field == 5: # TestDelay
                s.sendall(frame_message(f))
        except socket.timeout:
            break

    s.close()
    elapsed = time.perf_counter() - start_time

    if len(video_frames) > 1:
        gaps = [vf["gap_ms"] for vf in video_frames[1:]]
        gaps_sorted = sorted(gaps)
        p50 = statistics.median(gaps)
        p90 = gaps_sorted[int(len(gaps) * 0.90)]
        p95 = gaps_sorted[int(len(gaps) * 0.95)]
        p99 = gaps_sorted[int(len(gaps) * 0.99)]
        max_gap = max(gaps)
        min_gap = min(gaps)
        mean_gap = statistics.mean(gaps)
        jitter = statistics.stdev(gaps) if len(gaps) > 1 else 0.0
    else:
        p50 = p90 = p95 = p99 = max_gap = min_gap = mean_gap = jitter = 0.0

    fps = len(video_frames) / elapsed if elapsed > 0 else 0.0
    total_payload = sum(vf["bytes"] for vf in video_frames)

    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "target": f"{args.host}:{args.port}",
        "duration_s": round(elapsed, 3),
        "total_frames": len(video_frames),
        "total_bytes": total_payload,
        "fps": round(fps, 2),
        "stats_ms": {
            "min": round(min_gap, 2),
            "mean": round(mean_gap, 2),
            "p50": round(p50, 2),
            "p90": round(p90, 2),
            "p95": round(p95, 2),
            "p99": round(p99, 2),
            "max": round(max_gap, 2),
            "jitter": round(jitter, 2)
        },
        "frames": video_frames
    }

    if args.out_json:
        with open(args.out_json, "w", encoding="utf-8") as fp:
            json.dump(report, fp, indent=2)
        print(f"Benchmark saved to {args.out_json}")

    print(f"\n==========================================")
    print(f"BENCHMARK COMPLETED: {len(video_frames)} frames, {fps:.2f} FPS")
    print(f"Cadence p50: {p50:.2f}ms | p95: {p95:.2f}ms | p99: {p99:.2f}ms | Max: {max_gap:.2f}ms | Jitter: {jitter:.2f}ms")
    print(f"==========================================")

if __name__ == "__main__":
    main()

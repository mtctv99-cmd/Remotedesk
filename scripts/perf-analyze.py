#!/usr/bin/env python3
"""Summarize deskagent_perf trace markers into per-stage latency stats.

Reads log lines like (target `deskagent_perf`, level trace):
    perf stage=T3 seq=123 t_ms=1728300000123
and prints count/rate plus p50/p95/p99/max of per-stage INTER-ARRIVAL gaps,
plus a CSV with one row per marker.

Honest limits (see docs/PERFORMANCE_BENCHMARK_PLAN.md):
- Markers carry no input/frame id, so stages CANNOT be joined into end-to-end
  spans yet (that needs the id on the wire = v2-data-channel follow-up).
  This tool reports per-stage distributions only; any "E2E" column would be
  fabricated and is deliberately absent.
- Inter-arrival approximates stage cadence, not stage latency. Per-stage
  latency needs paired start/stop markers (follow-up in perf_probe.rs).

Usage:
    python3 scripts/perf-analyze.py deskagent.log
    python3 scripts/perf-analyze.py deskagent.log --csv out.csv
"""

import csv
import re
import sys
from collections import defaultdict

LINE_RE = re.compile(r"perf\s+stage=(T[1-7])\s+seq=(\d+)\s+t_ms=(\d+)(?:\s+trace_id=(\d+))?")


def percentile(sorted_vals, pct):
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    rank = (len(sorted_vals) - 1) * (pct / 100.0)
    low = int(rank)
    frac = rank - low
    high = min(low + 1, len(sorted_vals) - 1)
    return sorted_vals[low] * (1 - frac) + sorted_vals[high] * frac


def analyze(lines):
    per_stage = defaultdict(list)
    by_trace = defaultdict(dict)
    order = []
    for line in lines:
        m = LINE_RE.search(line)
        if not m:
            continue
        stage, seq, t_ms = m.group(1), int(m.group(2)), int(m.group(3))
        tid = int(m.group(4)) if m.group(4) else None
        per_stage[stage].append((t_ms, seq))
        order.append((stage, t_ms, seq, tid))
        if tid is not None:
            by_trace[tid][stage] = t_ms
    return per_stage, order, by_trace


def summarize_e2e(by_trace):
    e2e_spans = []
    for tid, stages in by_trace.items():
        if "T1" in stages and "T7" in stages:
            diff = stages["T7"] - stages["T1"]
            if diff >= 0:
                e2e_spans.append(diff)
    if not e2e_spans:
        return None
    e2e_spans.sort()
    return {
        "count": len(e2e_spans),
        "p50_ms": percentile(e2e_spans, 50),
        "p95_ms": percentile(e2e_spans, 95),
        "p99_ms": percentile(e2e_spans, 99),
        "max_ms": max(e2e_spans),
    }

def summarize(per_stage):
    rows = []
    for stage in sorted(per_stage):
        points = sorted(per_stage[stage])
        ts = [t for t, _ in points]
        gaps = [b - a for a, b in zip(ts, ts[1:])]
        gaps_sorted = sorted(gaps)
        span = (ts[-1] - ts[0]) / 1000.0 if len(ts) > 1 else 0.0
        rows.append(
            {
                "stage": stage,
                "count": len(ts),
                "rate_hz": (len(ts) / span) if span > 0 else 0.0,
                "gap_p50_ms": percentile(gaps_sorted, 50),
                "gap_p95_ms": percentile(gaps_sorted, 95),
                "gap_p99_ms": percentile(gaps_sorted, 99),
                "gap_max_ms": max(gaps) if gaps else None,
            }
        )
    return rows


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    csv_path = None
    for i, a in enumerate(argv[1:]):
        if a == "--csv" and i + 1 < len(argv[1:]):
            csv_path = argv[1:][i + 1]
    if not args:
        print(__doc__)
        return 2
    with open(args[0], encoding="utf-8", errors="replace") as f:
        per_stage, order, by_trace = analyze(f)
    rows = summarize(per_stage)
    if not rows:
        print("no deskagent_perf markers found")
        return 1
    print(f"{'stage':<6}{'count':>8}{'rate_hz':>10}"
          f"{'gap_p50':>10}{'gap_p95':>10}{'gap_p99':>10}{'gap_max':>10}")
    for r in rows:
        fmt = lambda v: ("%.2f" % v) if v is not None else "n/a"  # noqa: E731
        print(f"{r['stage']:<6}{r['count']:>8}{r['rate_hz']:>10.2f}"
              f"{fmt(r['gap_p50_ms']):>10}{fmt(r['gap_p95_ms']):>10}"
              f"{fmt(r['gap_p99_ms']):>10}{fmt(r['gap_max_ms']):>10}")
        e2e_stats = summarize_e2e(by_trace)
    if e2e_stats:
        print(f"\nE2E Latency (T1->T7, count={e2e_stats['count']}):")
        print(f"  p50: {e2e_stats['p50_ms']:.2f} ms | p95: {e2e_stats['p95_ms']:.2f} ms | p99: {e2e_stats['p99_ms']:.2f} ms | max: {e2e_stats['max_ms']:.2f} ms")
    if csv_path:
        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["stage", "t_ms", "seq", "trace_id"])
            w.writerows(order)
        print(f"wrote {csv_path} ({len(order)} markers)")
    return 0


def check_regression(baseline_p95, current_p95, current_fps=None, fps_min=58.5):
    """Kiểm tra cổng chặn hồi quy hiệu năng theo docs/PERFORMANCE_BENCHMARK_PLAN.md §5."""
    violations = []
    if baseline_p95 is not None and current_p95 is not None:
        max_allowed_p95 = baseline_p95 * 1.05  # Cổng 1: Latency p95 không vượt quá +5%
        if current_p95 > max_allowed_p95:
            violations.append(f"Latency regression: p95 {current_p95:.2f}ms exceeds +5% ceiling ({max_allowed_p95:.2f}ms)")
    if current_fps is not None and current_fps < fps_min:  # Cổng 2: FPS không dưới 58.5
        violations.append(f"Throughput regression: FPS {current_fps:.2f} below {fps_min} FPS threshold")
    return violations

def selftest():
    lines = [
        "x perf stage=T3 seq=1 t_ms=1000 y",
        "x perf stage=T3 seq=2 t_ms=1033 y",
        "x perf stage=T3 seq=3 t_ms=1066 y",
        "noise without markers",
        "x perf stage=T6 seq=9 t_ms=2000 y",
        "x perf stage=T1 seq=10 t_ms=3000 trace_id=101 y",
        "x perf stage=T7 seq=11 t_ms=3045 trace_id=101 y",
    ]
    per_stage, order, by_trace = analyze(lines)
    assert "T3" in per_stage and "T6" in per_stage and "T1" in per_stage, per_stage.keys()
    rows = {r["stage"]: r for r in summarize(per_stage)}
    assert rows["T3"]["count"] == 3
    assert rows["T3"]["gap_p50_ms"] == 33.0, rows["T3"]
    e2e = summarize_e2e(by_trace)
    assert e2e is not None
    assert e2e["count"] == 1
    assert e2e["p50_ms"] == 45.0, e2e

    # Kiểm tra regression gate (CI gating)
    assert len(check_regression(40.0, 41.0, 60.0)) == 0, "Passing regression check"
    reg_errs = check_regression(40.0, 43.0, 55.0)
    assert len(reg_errs) == 2, f"Expected 2 violations, got: {reg_errs}"
    print("selftest: OK")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        sys.exit(main(sys.argv))

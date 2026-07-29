#!/usr/bin/env python3
"""S4 — merge S1/S2/S3 outputs into runs/<run-name>/REPORT.md.

Usage: report.py <run-name>

Sections: per-stage aggregate table (from ground-truth SQL timeline),
per-machine stage breakdown, created→Ready totals, and the S1-vs-S2
cross-check that validates the I1 log instrumentation.
"""

import csv
import datetime as dt
import pathlib
import statistics
import sys
from collections import defaultdict

import os
RUNS_DIR = pathlib.Path(os.environ.get("BENCH_RUNS_DIR",
                                       pathlib.Path.home() / "stage-timing-runs"))


def read_csv(path):
    if not path.exists():
        return []
    with path.open() as fh:
        return list(csv.DictReader(fh))


def pct(values, p):
    if not values:
        return float("nan")
    values = sorted(values)
    idx = min(len(values) - 1, max(0, round(p / 100 * (len(values) - 1))))
    return values[idx]


def fmt(v):
    return "—" if v != v else (f"{v:.1f}" if isinstance(v, float) else str(v))


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: report.py <run-name>")
    run_dir = RUNS_DIR / name
    sql_rows = read_csv(run_dir / "timeline-sql.csv")
    loki_rows = read_csv(run_dir / "timeline-loki.csv")
    agg_rows = read_csv(run_dir / "stage-aggregates.csv")

    out = [f"# Stage-timing report — run `{name}`", ""]

    # --- per-stage aggregates from ground truth -----------------------------
    stage_dwells = defaultdict(list)
    for r in sql_rows:
        if r["dwell_s"]:
            stage_dwells[(r["state"], r["substate"])].append(float(r["dwell_s"]))
    out += ["## Per-stage dwell (ground truth: machine_state_history)", "",
            "| state | substate | n | min s | p50 s | p95 s | max s | sum s |",
            "|---|---|---|---|---|---|---|---|"]
    for (state, sub), ds in sorted(stage_dwells.items(),
                                   key=lambda kv: -sum(kv[1])):
        out.append(f"| {state} | {sub} | {len(ds)} | {min(ds):.1f} | "
                   f"{statistics.median(ds):.1f} | {pct(ds, 95):.1f} | "
                   f"{max(ds):.1f} | {sum(ds):.1f} |")

    # --- per-machine breakdown ----------------------------------------------
    per_machine = defaultdict(list)
    for r in sql_rows:
        per_machine[r["machine_id"]].append(r)
    out += ["", "## Per-machine timelines", ""]
    if len(per_machine) > 25:
        out += [f"({len(per_machine)} machines — full timelines omitted, "
                "see timeline-sql.csv; showing none to keep the report readable)", ""]
        per_machine = {}
    for mid, rows in sorted(per_machine.items()):
        total = sum(float(r["dwell_s"]) for r in rows if r["dwell_s"])
        final = rows[-1]
        out += [f"### `{mid}` — {len(rows)} transitions, "
                f"{total:.0f}s accounted, now in "
                f"`{final['state']}/{final['substate']}`", "",
                "| seq | state | substate | entered | dwell s |", "|---|---|---|---|---|"]
        out += [f"| {r['seq']} | {r['state']} | {r['substate']} | "
                f"{r['entered_at']} | {r['dwell_s'] or '…'} |" for r in rows]
        out.append("")

    # --- prometheus aggregates ----------------------------------------------
    if agg_rows:
        out += ["## Prometheus aggregates (window)", "",
                "| metric | state | substate | value |", "|---|---|---|---|"]
        out += [f"| {r['metric']} | {r['state']} | {r['substate']} | "
                f"{float(r['value']):.1f} |"
                for r in agg_rows if r["value"] not in ("", "NaN")]

    # --- S1 vs S2 cross-check (validates the I1 log) ------------------------
    # Semantics: every Loki event must correspond to a history row (Loki ⊆
    # SQL, matched per machine by entry timestamp ±2s). SQL legitimately has
    # MORE rows: machine_state_history records every controller_state write,
    # including out-of-band writers (site-explorer creation, discovery
    # handlers) that don't pass through the state controller's commit hook.
    out += ["", "## Cross-check: SQL history vs Loki transition log", ""]
    sql_ts = defaultdict(list)
    for r in sql_rows:
        try:
            t = dt.datetime.fromisoformat(r["entered_at"].replace("Z", "+00:00"))
            sql_ts[r["machine_id"]].append(t)
        except (ValueError, KeyError):
            pass
    # Objects with zero history rows were deleted before extraction (the log
    # outlives the DB row) — report them separately, they are not mismatches.
    ephemeral = defaultdict(int)
    matched = unmatched = 0
    per_machine_stats = defaultdict(lambda: [0, 0])  # machine -> [matched, total]
    for r in loki_rows:
        mid = r["machine_id"]
        if mid not in sql_ts:
            ephemeral[mid] += 1
            continue
        per_machine_stats[mid][1] += 1
        try:
            t = dt.datetime.fromisoformat(r["ts"])
        except ValueError:
            unmatched += 1
            continue
        if any(abs((t - s).total_seconds()) <= 2.0 for s in sql_ts.get(mid, [])):
            matched += 1
            per_machine_stats[mid][0] += 1
        else:
            unmatched += 1
    out += ["| machine | loki events matched in history | sql rows |", "|---|---|---|"]
    for mid in sorted(per_machine_stats):
        m, t = per_machine_stats[mid]
        out.append(f"| `{mid}` | {m}/{t} | {len(sql_ts.get(mid, []))} |")
    total = matched + unmatched
    verdict = ("NO DATA" if total == 0 else
               "PASS" if unmatched == 0 else
               f"FAIL ({unmatched}/{total} loki events without a matching history row)")
    out += ["", f"**Cross-check verdict: {verdict}**",
            "(loki events lag ~seconds; re-pull S2 if the run just ended)", ""]
    if ephemeral:
        out += [f"Ephemeral objects (deleted before extraction; log-only): "
                f"{len(ephemeral)} objects, {sum(ephemeral.values())} events — "
                "machines created then deleted mid-run (e.g. preliminary hosts "
                "replaced on expected-machine re-registration).", ""]

    report = run_dir / "REPORT.md"
    report.write_text("\n".join(out))
    print(f"S4 OK: {report} (cross-check: {verdict})")


if __name__ == "__main__":
    main()

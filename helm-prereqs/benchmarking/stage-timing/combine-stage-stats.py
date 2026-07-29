#!/usr/bin/env python3
"""Combine SQL / Loki / Prometheus extractions into ONE per-stage stats CSV.

Usage: combine-stage-stats.py <run-name>

Reads runs/<run>/timeline-sql.csv, timeline-loki.csv, stage-aggregates.csv and
writes runs/<run>/stage-stats.csv — one row per (state, substate):

  state, substate,
  n_sql, dwell_min_s, dwell_p50_s, dwell_p95_s, dwell_max_s, dwell_sum_s,   <- SQL ground truth
  n_loki, loki_p50_s,                                                       <- I1 transition log
  prom_entered, prom_p50_s, prom_p95_s,                                     <- Prometheus (TSDB)
  flags                                                                     <- discrepancy flags

Flag semantics (empty = all sources agree):
  LOKI_MISSING       loki has no events for a stage sql saw exits from
  COUNT_DRIFT        |n_sql_exits - n_loki| > expected out-of-band writes
  P50_DRIFT          sql vs loki p50 differ by >10% and >2s
  PROM_ABSENT        prometheus has no series for the stage (scrape gap?)
  PROM_COUNT_DRIFT   prometheus entered-count differs from loki events
  SQL_OPEN           stage never exited during the window (dwell incomplete;
                     stats cover completed visits only)

Vocabulary note: SQL uses the serde tags (e.g. dpudiscoveringstate /
initializing); Loki+Prometheus use metric_state_names (dpudiscovering /
dpuinitializing). States map 1:1 via STATE_ALIASES. SUBSTATES DO NOT JOIN
across sources by design: the SQL timeline aggregates the per-DPU map
(compound labels like "configuring+initializing"), while the controller's
metrics/log use the least-progressed DPU only ("configuring"). Cross-source
flags are therefore computed at STATE level (substate="*"), where the
vocabularies agree; substate rows carry per-source detail without
cross-source flags.
"""

import csv
import pathlib
import statistics
import sys
from collections import defaultdict

import os
RUNS_DIR = pathlib.Path(os.environ.get("BENCH_RUNS_DIR",
                                       pathlib.Path.home() / "stage-timing-runs"))

# metric/log vocabulary -> DB serde-tag vocabulary (state level)
STATE_ALIASES = {
    "dpudiscovering": "dpudiscoveringstate",
    "dpunotready": "dpuinit",
    "hostnotready": "hostinit",
    "hostinit": "hostinit",
    "created": "created",
    "ready": "ready",
    "waitingforcleanup": "waitingforcleanup",
    "validation": "validation",
    "bomvalidating": "bomvalidating",
}
# substate level (log/metric name -> DB name); identity if absent
SUBSTATE_ALIASES = {
    "dpuinitializing": "initializing",
    "dpuconfiguring": "configuring",
}


def norm_metric(state, substate):
    return (STATE_ALIASES.get(state, state),
            SUBSTATE_ALIASES.get(substate, substate))


def read_csv(path):
    if not path.exists():
        return []
    with path.open() as fh:
        return list(csv.DictReader(fh))


def pct(vals, p):
    vals = sorted(vals)
    if not vals:
        return None
    return vals[min(len(vals) - 1, max(0, round(p / 100 * (len(vals) - 1))))]


def fnum(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: combine-stage-stats.py <run-name>")
    run_dir = RUNS_DIR / sys.argv[1]
    sql_rows = read_csv(run_dir / "timeline-sql.csv")
    loki_rows = read_csv(run_dir / "timeline-loki.csv")
    agg_rows = read_csv(run_dir / "stage-aggregates.csv")

    # --- SQL: completed dwells + open (never-exited) visits per stage -------
    sql_dwell = defaultdict(list)
    sql_open = defaultdict(int)
    for r in sql_rows:
        key = (r["state"], r["substate"])
        if r["dwell_s"]:
            sql_dwell[key].append(float(r["dwell_s"]))
        else:
            sql_open[key] += 1

    # --- Loki: dwell_ms is time in the *from* stage --------------------------
    # Machines get RENAMED mid-ingest (expected-machine adoption): the DB
    # migrates machine_state_history rows to the new id, but the already-
    # emitted log events keep the old id. Re-attribute each log-only id to
    # the surviving machine whose history timestamps match its events (±2s);
    # ids with no such match are truly ephemeral and excluded.
    import datetime as _dt

    def _ts(s):
        try:
            return _dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            return None

    sql_machines = {r["machine_id"] for r in sql_rows}
    sql_times = defaultdict(list)
    for r in sql_rows:
        t = _ts(r["entered_at"])
        if t:
            sql_times[r["machine_id"]].append(t)
    loki_by_old = defaultdict(list)
    for r in loki_rows:
        if r["machine_id"] not in sql_machines:
            loki_by_old[r["machine_id"]].append(r)
    rename_map, ephemeral_events = {}, 0
    for old_id, evs in loki_by_old.items():
        ev_ts = [t for t in (_ts(r["ts"]) for r in evs) if t]
        best_id, best_frac = None, 0.0
        for mid, times in sql_times.items():
            hits = sum(1 for t in ev_ts
                       if any(abs((t - s).total_seconds()) <= 2.0 for s in times))
            frac = hits / len(ev_ts) if ev_ts else 0.0
            if frac > best_frac:
                best_id, best_frac = mid, frac
        if best_id and best_frac >= 0.8:
            rename_map[old_id] = best_id
        else:
            ephemeral_events += len(evs)
    loki_rows = [
        ({**r, "machine_id": rename_map[r["machine_id"]]}
         if r["machine_id"] in rename_map else r)
        for r in loki_rows
        if r["machine_id"] in sql_machines or r["machine_id"] in rename_map
    ]
    if rename_map:
        print(f"re-attributed {len(rename_map)} renamed machine ids "
              f"(old->new): {len([r for r in loki_rows])} events total")
    loki_dwell = defaultdict(list)
    loki_entered = defaultdict(int)  # by TO state — comparable to prom entered
    for r in loki_rows:
        key = norm_metric(r["from_state"], r["from_substate"])
        ms = fnum(r["dwell_ms"])
        if ms is not None:
            loki_dwell[key].append(ms / 1000.0)
        to_state, _ = norm_metric(r["to_state"], r["to_substate"])
        loki_entered[to_state] += 1

    # --- Prometheus: pivot metric rows to per-stage columns ------------------
    prom = defaultdict(dict)
    for r in agg_rows:
        state = r["state"].strip('"')
        sub = r["substate"].strip('"')
        key = norm_metric(state, sub)
        v = fnum(r["value"].strip('"') if r["value"] else None)
        prom[key][r["metric"].strip('"')] = v

    # Drop prometheus stages that only carry handler latency with no state
    # identity (state="unknown" comes from pre-first-load handler samples).
    prom = {k: v for k, v in prom.items() if k[0] and k[0] != "unknown"}

    def rollup(dwells_by_key, extra=lambda k: True):
        by_state = defaultdict(list)
        for (state, _sub), vals in dwells_by_key.items():
            by_state[state].extend(vals)
        return by_state

    sql_by_state = rollup(sql_dwell)
    loki_by_state = rollup(loki_dwell)
    open_by_state = defaultdict(int)
    for (state, _s), n in sql_open.items():
        open_by_state[state] += n
    prom_entered_by_state = defaultdict(float)
    prom_seen_states = set()
    for (state, _s), pm in prom.items():
        prom_seen_states.add(state)
        if pm.get("entered_total") is not None:
            prom_entered_by_state[state] += pm["entered_total"]

    def stats_cells(ds):
        if not ds:
            return ["0", "", "", "", "", ""]
        return [str(len(ds)), f"{min(ds):.2f}", f"{statistics.median(ds):.2f}",
                f"{pct(ds, 95):.2f}", f"{max(ds):.2f}", f"{sum(ds):.2f}"]

    out_path = run_dir / "stage-stats.csv"
    with out_path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["state", "substate",
                    "n_sql", "dwell_min_s", "dwell_p50_s", "dwell_p95_s",
                    "dwell_max_s", "dwell_sum_s",
                    "n_loki", "loki_p50_s",
                    "prom_entered", "prom_p50_s", "prom_p95_s", "flags"])

        # --- state-level rows (substate="*"): the cross-validated view ------
        states = sorted(set(sql_by_state) | set(loki_by_state)
                        | set(open_by_state) | prom_seen_states)
        for state in states:
            ds, ls = sql_by_state.get(state, []), loki_by_state.get(state, [])
            flags = []
            if open_by_state.get(state):
                flags.append(f"SQL_OPEN({open_by_state[state]})")
            if ds and not ls and state != "created":
                # 'created' is written by site-explorer, never the controller
                flags.append("LOKI_MISSING")
            if ds and ls and abs(len(ds) - len(ls)) > max(2, 0.2 * len(ds)):
                flags.append(f"COUNT_DRIFT(sql={len(ds)}/loki={len(ls)})")
            if ds and ls:
                sp, lp = statistics.median(ds), statistics.median(ls)
                if abs(sp - lp) > 2 and abs(sp - lp) > 0.1 * max(sp, lp):
                    flags.append(f"P50_DRIFT(sql={sp:.1f}/loki={lp:.1f})")
            if ls and state not in prom_seen_states:
                flags.append("PROM_ABSENT")
            pe = prom_entered_by_state.get(state)
            le = loki_entered.get(state, 0)
            if pe is not None and le and abs(pe - le) > 0.5:
                flags.append(f"PROM_COUNT_DRIFT(prom={pe:.0f}/loki={le})")
            w.writerow([state, "*", *stats_cells(ds),
                        str(len(ls)),
                        f"{statistics.median(ls):.2f}" if ls else "",
                        f"{pe:.0f}" if pe is not None else "", "", "",
                        ";".join(flags)])

        # --- substate detail rows: per-source, no cross-source flags --------
        detail_keys = sorted(set(sql_dwell) | set(sql_open) | set(loki_dwell)
                             | set(prom))
        for key in detail_keys:
            state, sub = key
            ds, ls, pm = (sql_dwell.get(key, []), loki_dwell.get(key, []),
                          prom.get(key, {}))
            flags = [f"SQL_OPEN({sql_open[key]})"] if sql_open.get(key) else []
            pe = pm.get("entered_total")
            w.writerow([
                state, sub, *stats_cells(ds),
                str(len(ls)),
                f"{statistics.median(ls):.2f}" if ls else "",
                f"{pe:.0f}" if pe is not None else "",
                f"{pm.get('dwell_p50_s'):.2f}" if pm.get("dwell_p50_s") is not None else "",
                f"{pm.get('dwell_p95_s'):.2f}" if pm.get("dwell_p95_s") is not None else "",
                ";".join(flags),
            ])
    note = (f" (excluded {ephemeral_events} events from ephemeral/deleted objects)"
            if ephemeral_events else "")
    print(f"combined {len(states)} states / {len(detail_keys)} substate rows -> {out_path}{note}")


if __name__ == "__main__":
    main()

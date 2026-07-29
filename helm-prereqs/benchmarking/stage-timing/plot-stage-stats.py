#!/usr/bin/env python3
"""Render the stage-timing artifacts into PNG charts. Pure script — no
interpretation: what you see is computed from timeline-sql.csv (ground truth)
and stage-stats.csv.

Usage:
  plot-stage-stats.py <run> [<run2> ...]

Per run (written to runs/<run>/plots/):
  gantt.png         per-machine stage timeline (who spent time where)
  stage-totals.png  total dwell per stage (where the run's time went)
  stage-ranges.png  per-stage dwell min–p50–p95 (consistency within the run)

With ≥2 runs, additionally writes runs/_comparisons/<run1>-vs-…png:
  per-stage median dwell, one bar group per stage, one color per run.
"""

import csv
import datetime as dt
import pathlib
import statistics
import sys
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import os
RUNS_DIR = pathlib.Path(os.environ.get("BENCH_RUNS_DIR",
                                       pathlib.Path.home() / "stage-timing-runs"))

# Fixed pipeline order + validated categorical palette (dataviz reference
# instance, light mode). Color follows the stage everywhere.
STAGES = [
    ("created", "#4a3aa7"),
    ("dpudiscoveringstate", "#2a78d6"),
    ("dpuinit", "#eb6834"),
    ("hostinit", "#1baf7a"),
    ("waitingforcleanup", "#eda100"),
    ("bomvalidating", "#e87ba4"),
    ("validation", "#008300"),
]
STAGE_COLOR = dict(STAGES)
STAGE_ORDER = [s for s, _ in STAGES]
RUN_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]  # ≤4 runs compared

INK, INK2, GRID = "#1a1a19", "#5f5e56", "#e7e6e0"


def style_axes(ax):
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=9)
    ax.xaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def read_timeline(run):
    path = RUNS_DIR / run / "timeline-sql.csv"
    rows = []
    with path.open() as fh:
        for r in csv.DictReader(fh):
            r["_t0"] = dt.datetime.fromisoformat(r["entered_at"].replace("Z", "+00:00"))
            r["_dwell"] = float(r["dwell_s"]) if r["dwell_s"] else None
            rows.append(r)
    return rows


def plot_gantt(run, rows, outdir):
    t_first = min(r["_t0"] for r in rows)
    machines = sorted({r["machine_id"] for r in rows})
    fig, ax = plt.subplots(figsize=(11, 0.55 * len(machines) + 2.2))
    seen_states = []
    for i, mid in enumerate(machines):
        for r in rows:
            if r["machine_id"] != mid or r["_dwell"] is None:
                continue
            start = (r["_t0"] - t_first).total_seconds() / 60.0
            width = max(r["_dwell"] / 60.0, 0.02)
            color = STAGE_COLOR.get(r["state"], "#c3c2b7")
            ax.barh(i, width, left=start, height=0.62, color=color,
                    edgecolor="white", linewidth=1.0)
            if r["state"] not in seen_states:
                seen_states.append(r["state"])
    ax.set_yticks(range(len(machines)))
    ax.set_yticklabels([m[:14] + "…" for m in machines], fontsize=8,
                       fontfamily="monospace", color=INK2)
    ax.invert_yaxis()
    ax.set_xlabel("minutes since first transition", color=INK2, fontsize=9)
    ax.set_title(f"{run} — per-machine stage timeline (SQL ground truth)",
                 color=INK, fontsize=11, loc="left")
    handles = [plt.Rectangle((0, 0), 1, 1, color=STAGE_COLOR[s])
               for s in STAGE_ORDER if s in seen_states]
    ax.legend(handles, [s for s in STAGE_ORDER if s in seen_states],
              loc="upper center", bbox_to_anchor=(0.5, -0.14),
              ncol=min(4, len(handles)), fontsize=8, frameon=False,
              labelcolor=INK2)
    style_axes(ax)
    fig.tight_layout()
    fig.savefig(outdir / "gantt.png", dpi=140)
    plt.close(fig)


def stage_dwells(rows):
    d = defaultdict(list)
    for r in rows:
        if r["_dwell"] is not None:
            d[r["state"]].append(r["_dwell"])
    return d


def plot_totals(run, dwells, outdir):
    stages = [s for s in STAGE_ORDER if s in dwells and sum(dwells[s]) > 0]
    totals = [sum(dwells[s]) for s in stages]
    fig, ax = plt.subplots(figsize=(9, 0.5 * len(stages) + 1.8))
    ax.barh(range(len(stages)), totals,
            color=[STAGE_COLOR[s] for s in stages], height=0.55,
            edgecolor="white", linewidth=1.0)
    for i, v in enumerate(totals):
        ax.text(v, i, f"  {v:,.0f}s", va="center", fontsize=9, color=INK2)
    ax.set_yticks(range(len(stages)))
    ax.set_yticklabels(stages, fontsize=9, color=INK)
    ax.invert_yaxis()
    ax.set_xlabel("total dwell across all machines (seconds)", color=INK2, fontsize=9)
    ax.set_title(f"{run} — where the run's time went", color=INK,
                 fontsize=11, loc="left")
    style_axes(ax)
    ax.margins(x=0.12)
    fig.tight_layout()
    fig.savefig(outdir / "stage-totals.png", dpi=140)
    plt.close(fig)


def pct(vals, p):
    vals = sorted(vals)
    return vals[min(len(vals) - 1, max(0, round(p / 100 * (len(vals) - 1))))]


def plot_ranges(run, dwells, outdir):
    stages = [s for s in STAGE_ORDER if s in dwells and dwells[s]]
    fig, ax = plt.subplots(figsize=(9, 0.5 * len(stages) + 1.8))
    for i, s in enumerate(stages):
        v = dwells[s]
        lo, mid, hi = min(v), statistics.median(v), pct(v, 95)
        ax.plot([lo, hi], [i, i], color=STAGE_COLOR[s], linewidth=2,
                solid_capstyle="round")
        ax.plot([mid], [i], "o", color=STAGE_COLOR[s], markersize=9,
                markeredgecolor="white", markeredgewidth=1.5)
        ax.text(hi, i, f"  p50 {mid:.1f}s · p95 {hi:.1f}s",
                va="center", fontsize=8.5, color=INK2)
    ax.set_yticks(range(len(stages)))
    ax.set_yticklabels(stages, fontsize=9, color=INK)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_xlabel("dwell per visit, seconds (log scale) — min–p95 range, dot = median",
                  color=INK2, fontsize=9)
    ax.set_title(f"{run} — dwell distribution per stage", color=INK,
                 fontsize=11, loc="left")
    style_axes(ax)
    ax.margins(x=0.25)
    fig.tight_layout()
    fig.savefig(outdir / "stage-ranges.png", dpi=140)
    plt.close(fig)


def plot_comparison(runs, all_dwells):
    stages = [s for s in STAGE_ORDER
              if any(all_dwells[r].get(s) for r in runs)]
    n = len(runs)
    fig, ax = plt.subplots(figsize=(10, 0.34 * len(stages) * n + 2))
    for j, run in enumerate(runs):
        ys, vals = [], []
        for i, s in enumerate(stages):
            v = all_dwells[run].get(s, [])
            ys.append(i + (j - (n - 1) / 2) * (0.7 / n))
            vals.append(statistics.median(v) if v else 0)
        ax.barh(ys, vals, height=0.7 / n - 0.04, color=RUN_COLORS[j % 4],
                edgecolor="white", linewidth=0.8, label=run)
    ax.set_yticks(range(len(stages)))
    ax.set_yticklabels(stages, fontsize=9, color=INK)
    ax.invert_yaxis()
    ax.set_xlabel("median dwell per visit (seconds)", color=INK2, fontsize=9)
    ax.set_title("run comparison — per-stage median dwell", color=INK,
                 fontsize=11, loc="left")
    ax.legend(loc="lower right", fontsize=8.5, frameon=False, labelcolor=INK2)
    style_axes(ax)
    out = RUNS_DIR / "_comparisons"
    out.mkdir(exist_ok=True)
    name = "-vs-".join(runs) + ".png"
    fig.tight_layout()
    fig.savefig(out / name, dpi=140)
    plt.close(fig)
    return out / name


def main():
    runs = sys.argv[1:]
    if not runs:
        sys.exit("usage: plot-stage-stats.py <run> [<run2> ...]")
    all_dwells = {}
    for run in runs:
        rows = read_timeline(run)
        outdir = RUNS_DIR / run / "plots"
        outdir.mkdir(exist_ok=True)
        dwells = stage_dwells(rows)
        all_dwells[run] = dwells
        plot_gantt(run, rows, outdir)
        plot_totals(run, dwells, outdir)
        plot_ranges(run, dwells, outdir)
        print(f"{run}: 3 charts -> {outdir}")
    if len(runs) >= 2:
        print(f"comparison -> {plot_comparison(runs, all_dwells)}")


if __name__ == "__main__":
    main()

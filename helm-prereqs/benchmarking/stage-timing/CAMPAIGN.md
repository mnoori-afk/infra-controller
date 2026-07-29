# Ingestion knob campaign — run plan & tracker

Run plan for characterizing machine-ingestion scaling on a real multi-node
Kubernetes cluster with this toolkit, and the live tracker to update as runs
complete. Methodology and the single-node validation that seeded this plan:
[validated-results/LADDER-ANALYSIS.md](validated-results/LADDER-ANALYSIS.md).

**Protocol.** Every run is a fresh install (`run-full-benchmark-k8s.sh`, lean
`--skip-rest` posture, observability stack on, reinstall per run — recycled
clusters are a known confounder). Knob changes are applied by installing from a
per-run variant of the site Core values file (`CORE_VALUES`), NOT by patching a
live site: with reinstall-per-run this is both simpler and immune to the
env-override patcher's current section-collision defect.

**Held constant across all runs** (site values): `site_explorer.run_interval =
30s`, `max_concurrent_machine_updates = 20`, `firmware_global.autoupdate =
false`, `allow_insecure_discovery = true` (test-only, machine-a-tron single-IP
mode). Fleet shape is always `hosts × 2 DPUs` → `machines = hosts × 3`.

**Where results live.** Each run writes to `$BENCH_RUNS_DIR/<run>/` (default
`~/stage-timing-runs/<run>/`, never committed): `stage-stats.csv` (the
headline, three-channel cross-validated), `timeline-sql.csv`,
`timeline-loki.csv`, `stage-aggregates.csv`, `REPORT.md` (PASS/FAIL verdict),
`plots/*.png`, and the phase logs (`clean.log`, `setup.log`, `mat.log`,
`timing.log`, `full-benchmark.log`). When a run's cross-check passes and it
becomes part of the record, promote its `stage-stats.csv` into
`validated-results/` as `stage-stats-<run>.csv` and update this tracker.

---

## Phase A — scale ladder, knobs fixed (find the knee)

Fleet size is the only variable. Mirrors the single-node ladder rungs for
direct comparison; A4 doubles as the Phase-B control.

| Run | hosts×dpus | machines | knobs | status | verdict / notes |
|---|---|---|---|---|---|
| smoke-5x2 | 5×2 | 15 | site defaults | **done 2026-07-29** | cross-check PASS on a warm cluster; per-host stage profile within 1% of the single-node anchor (hostinit 447 s, cleanup latch p50 144 s, quantum ~2.5 s) |
| fresh-5x2-r1 | 5×2 | 15 | site defaults | **done 2026-07-29** | ALL-READY in 17 min, cross-check PASS, full cycle 49 min. Per-host 1012 s (+8% vs warm smoke, concentrated in hostinit/dpuinit; cleanup latch p50 144.7 s identical). CSV: validated-results/stage-stats-k8s-fresh-5x2-r1.csv |
| scale-25x2 | 25×2 | 75 | site defaults | todo | single-node knee appeared here |
| scale-50x2 | 50×2 | 150 | site defaults | todo | |
| scale-100x2 | 100×2 | 300 | site defaults | todo | becomes Phase-B control (B0) |
| scale-167x2 | 167×2 | 501 | site defaults | todo | single-node wall clock bent here (26→40 min) |

**Decision point after scale-167x2:** does the dispatch quantum double per
fleet doubling with a knee near 75 machines (the single-node signature)? If
yes, Phase B as planned; if the knee moves, re-center Phase B's rung on it.

## Phase B — single-knob runs at the measurement rung (100×2 = 300 machines)

One knob changed per run vs the B0 control, in the site-config TOML.

| Run | knob (TOML) | default → test | hosts×dpus | machines | status | verdict / notes |
|---|---|---|---|---|---|---|
| B0 = scale-100x2 | — (control) | — | 100×2 | 300 | todo | shared with Phase A |
| B1-stmc-50 | `[machine_state_controller] max_concurrency` | default (10) → **50** | 100×2 | 300 | todo | headline: does controller queueing collapse? |
| B2-stmc-100 | `[machine_state_controller] max_concurrency` | default (10) → **100** | 100×2 | 300 | todo | ceiling test: `COMMAND_BUFFER_SIZE = 100` caps effect |
| B3-mcpr-40 | `[site_explorer] machines_created_per_run` | default → **40** | 100×2 | 300 | todo | creation-wave shape |
| B4-mcpr-100 | `[site_explorer] machines_created_per_run` | default → **100** | 100×2 | 300 | todo | creation fully uncorked |
| B5-explorer | `[site_explorer] concurrent_explorations` / `explorations_per_run` | defaults → **100 / 120** | 100×2 | 300 | todo | closes out the exploration-knob hypothesis (single-node run showed no knee there) |
| B6-winners | best of B1–B5 combined | — | 100×2 | 300 | todo | interaction check |

**Skipped with rationale:** `firmware_global.run_interval` /
`concurrency_limit` — `autoupdate = false` in the benchmarking posture, so
firmware jobs never run during ingestion and these knobs are no-ops here.
`site_explorer.run_interval` — already at the 30s scale profile in the held
values; raising it only slows runs and carries no scaling information.

## Phase C — confirmation at scale

| Run | config | hosts×dpus | machines | status | verdict / notes |
|---|---|---|---|---|---|
| C1-winners-167x2 | B6 winners | 167×2 | 501 | todo | expect large improvement vs scale-167x2 |
| C2-winners-500x2 | B6 winners | 500×2 | 1,500 | todo | probes past the single-node ladder's edge |

## Repeats (variance)

| Run | duplicates | status | verdict / notes |
|---|---|---|---|
| scale-100x2-r2 | B0 control | todo | run-over-run variance at the measurement rung |
| C1-winners-167x2-r2 | C1 | todo | variance of the winning config |

# Ingestion tuning results (#3738)

Append-only log of the one-knob-at-a-time campaign runs. One row per
`run-ingestion-benchmark.sh` invocation; the run matrix and method live in
[machine-a-tron-ingestion-tuning-plan.md](machine-a-tron-ingestion-tuning-plan.md).

Per-run artifacts (CSV, setup log, DB-clock rate report, Prometheus pulls) are in the
runner's results dir (`RESULTS_ROOT`, default `~/mat-bench-results/<run>-<stamp>`); this
file records the comparison table and the observations that numbers alone don't carry.

## Runs

| Run | Date (UTC) | Site | Fleet | Knob change vs B0 | Wall clock | Creation rate (avg/min) | machines_ready @end | Notes |
|-----|------------|------|-------|-------------------|------------|-------------------------|---------------------|-------|
| B0  |            |      | 1000×2 | — (baseline: K1=120s K2=100 K3=120 K4=40 K5=16 K6=30s K7=10) | | | | |
| E1  |            |      | 1000×2 | K1 120s → 30s     | | | | |
| E2  |            |      | 1000×2 | K4 40 → 100       | | | | |
| E3a |            |      | 1000×2 | K3 120 → 240      | | | | |
| E3b |            |      | 1000×2 | K3 240 → 360      | | | | |
| E4a |            |      | 1000×2 | K2 100 → 200      | | | | |
| E4b |            |      | 1000×2 | K2 200 → 400      | | | | |
| E5a |            |      | 1000×2 | K5 16 → 32        | | | | |
| E5b |            |      | 1000×2 | K5 32 → 64        | | | | |
| E6a |            |      | 1000×2 | K7 10 → 50        | | | | |
| E6b |            |      | 1000×2 | K7 50 → 100       | | | | |
| E7  |            |      | 1000×2 | combined winners  | | | | |
| E7-confirm | |         | 4500×2 | combined winners  | | | | |

## Per-run observations

Template — copy per run:

### <RUN> — <date>

- **Per-phase windows** (from `rate-report.txt` + the CSV summary): DHCP … / exploration … /
  preingestion … / creation … / init …
- **Cycle behavior**: did explore cycles complete within `run_interval`? (`se_cycle` summary line
  and the dashboard's "cycle vs K1" panel)
- **Postgres**: CPU peak, any lock contention / AvoidLockout or error storms.
- **Verdict**: keep / revert; interaction risks for E7.

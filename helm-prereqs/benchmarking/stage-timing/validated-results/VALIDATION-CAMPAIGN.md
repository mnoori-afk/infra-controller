> Snapshot from the k3s dev-rig campaign, taken 2026-07-29 ~16:20Z.
> Ladder complete through 501 machines (scale-167x2); the 999-machine
> rung (scale-333x2) was still ingesting — live originals on the dev box.

# Validation campaign — prove the stage-timing data is real

Started 2026-07-28 evening. Goal: run small ingests repeatedly and iterate on
instrumentation + scrapers until every number is cross-validated across the
three sources, then declare the rig trustworthy for real benchmarking.

## The deliverable per run

`runs/<run>/stage-stats.csv` (from `scripts/combine-stage-stats.py`) — ONE CSV:
- `substate="*"` rows: the **cross-validated state-level view** — SQL ground
  truth (n, min/p50/p95/max/sum dwell), Loki event count + p50, Prometheus
  entered count — with automatic discrepancy `flags`.
- substate rows: per-source detail (SQL uses compound per-DPU labels,
  Loki/Prom use the controller's least-progressed label — different
  vocabularies by design, so no cross-flags at this level).

## Loop protocol (each iteration)

1. `cleanup-machine-a-tron.sh -y` (restarts nico-api → counters reset = per-run)
2. record `window-start` → `MAT_MODE=scale HOST_COUNT=5 DPU_PER_HOST=2 setup` →
   watcher until ready=15 / failed>0 / timeout
3. `sql-stage-timeline.sh <run> <from> <to>` + `loki-stage-timeline.py` +
   `prom-stage-aggregates.sh` + `report.py` + `combine-stage-stats.py`
4. Analyze `flags` column + REPORT.md cross-check verdict.
   Every unexplained flag = a bug in instrumentation, scraper, or my model of
   the system → diagnose, fix, record below, rerun.

## Convergence criteria (campaign done when ALL hold on 2 consecutive runs)

- C1 fleet reaches `ready` 15/15 (full path covered, created→ready populated)
- C2 REPORT.md cross-check verdict PASS (every Loki event ⊆ SQL ±2s)
- C3 `stage-stats.csv` state-level rows: zero flags except explainable
  `SQL_OPEN` during mid-run extraction (none at end-of-run)
- C4 per machine: Σ(SQL dwells) ≈ created→ready wall clock within 5%
- C5 Prometheus `created_to_ready_count` == 5 and its p50 consistent with C4
- C6 run-over-run: stage medians within noise (< ~30%) between the 2 runs

## Fix log (bugs found by the loop — keep appending)

| # | Found | Symptom → root cause → fix |
|---|---|---|
| 1 | run 1 | Loki CSV empty → `re.findall` returns `''` not None for alt groups → `q or b` |
| 2 | run 1 | Prom aggregates all 0 → burst finished before first scrape of restarted pod; `increase()` blind → absolute values (valid: restart-per-run) |
| 3 | run 1 | SQL timeline mixed in July-22 data → deterministic MAT machine ids reuse prior fleet's history → mandatory window filter on S1 |
| 4 | runs 1–2 | fleet wedges in `dpuinit`: 100% DiscoverMachine NICO-API-403 (source-IP ≠ interface IP; MAT single-IP mode) → `allow_insecure_discovery = true` in dev site-config (documented for exactly this) |
| 5 | run 1 | combiner: substate vocabularies don't join (SQL compound per-DPU vs controller min-label) → cross-validate at state level only |
| 6 | run 1 | combiner: compared prom *entries* to loki *exits* → count by `to_state` for that comparison |
| 7 | run 3 | S2 captured other controllers' transitions (the log is generic) → filter `controller="machine_state_controller"` |
| 8 | run 3 | **discovery, not a bug**: machines are RENAMED mid-ingest (expected-machine adoption, all 5 hosts at once, at the dpuinit→hostinit boundary). The DB migrates `machine_state_history` to the new id (`state_history::update_object_ids`); already-emitted logs keep the old id. Combiner now re-attributes old→new via ±2s timestamp matching (all 5 matched ≥80%); report lists true ephemerals separately. Also epic-relevant: every ingest walks 2× hosts through dpudiscovering (preliminary + adopted identity). |
| 9 | run 3 | missing state alias `hostnotready` (HostInit's metric name) → added |
| 10 | fresh-r1 | prometheus-operator missed the Prometheus CR on fresh install (CRD-registration race) → server StatefulSet never created, run's metrics lost. Workaround baked into the pipeline: wait for the sts, restart the operator if absent |
| 11 | fresh-r1 | upstream chart index dropped postgres-operator 1.10.1 → **fixed upstream** (user's MR bumps the pin with rationale); deploy repo rebased onto latest origin/main (`9cb955f5d`), local tarball workaround dropped. NOTE: setup now installs the *latest* nico chart before phase 4 swaps to the pinned chart — watch for install-time chart/image skew symptoms in setup.log |

## Run ledger

| Run | MAT tag | Outcome |
|---|---|---|
| smoke-5x2 | c06f4787a-amd64 | creation ✅ / cross-check PASS / wedged dpuinit (fix 4 not yet applied) |
| smoke-5x2-v2 | v2.1.0-pr-310-gb20d9f43c | same wedge → disproved MAT-tag theory; no extraction |
| smoke-5x2-v3 | v2.1.0-pr-310-gb20d9f43c + allow_insecure_discovery | ✅ **15/15 ready in 17 min**; cross-check PASS; created→ready count=5 p50=900s; stage-stats fully reconciled (C1–C5 ✅) |
| smoke-5x2-v4 | same | ✅ 15/15 ready in 16 min; PASS; identical stage counts vs v3 (55/30/105/5/5/10); medians within 1–15% → **C6 ✅ — C1–C6 ALL SATISFIED on warm-cluster protocol (2026-07-29)** |
| fresh-5x2-r1 | same, fresh cluster (just clean) | ⚠️ partial: 15/15 ready in 17 min, SQL+Loki extracted (same 220/210/10-object shape as warm runs) but Prometheus leg lost to fix #10 — superseded by the pipeline runs |
| fresh-5x2-r2 | **one-command pipeline** (`run-full-benchmark.sh`, restructured phases: prereqs `--skip-core` → core once from pinned chart + published `-instrumented` image) on rebased-main deploy repo, fully fresh cluster | ✅ **bare metal → results in 32 min** (12 min install + 17 min ingest + extraction). 15/15 ready; cross-check PASS; zero unexplained flags; created→ready p50=900s. **Stage sums within ~5% of warm anchors** (dpudisc 131 vs 126/137; dpuinit 816 vs 820/784; hostinit 2211 vs 2363/2268; cleanup 1447 vs 1445/1431) → **fresh-cluster numbers ≡ warm-cluster numbers: no cluster-state bias on this box** |

## Phase 2 (user-directed): from-scratch consistency

Warm-cluster convergence ≠ from-scratch consistency (Shayan's campaign died on
exactly this: recycled clusters degrade). New protocol per run: `just clean` in
`~/forged` (env `local-dev`: uninstall-k3s → install-k3s with the same
`--docker --disable=traefik --disable=servicelb` flags → kubeconfig) → full
stack reinstall (`setup.sh --single-node-k3s` + observability +
`helm upgrade` to the smt image + the two dev-values knobs) → 5×2 run →
extraction → compare stage stats against the warm-cluster anchors (v3/v4).
Local docker images survive (daemon untouched). Loki/Prometheus history is
lost each recreation — extraction must complete before the next clean (it
does, per-run).

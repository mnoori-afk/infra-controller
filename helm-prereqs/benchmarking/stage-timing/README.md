# Stage-timing benchmarking toolkit

Measure, per machine and per stage, how long the machine state machine takes
during ingestion — and prove the numbers are real by cross-validating three
independent data channels. Built and field-validated on a single-node k3s dev
rig (5→999-machine sweeps); this copy is adapted for real clusters and pairs
with the site-local observability stack in `../../observability/`.

## What the instrumentation emits (in this branch's code)

The companion code commit adds, on top of the existing state-controller
telemetry:

| Signal | Where | What it answers |
|---|---|---|
| `state_transition_committed` info log — object_id, from/to state+substate, `dwell_ms` | state-controller processor, fired **only after the transition's transaction commits** | per-machine stage timelines from the log store, immune to metric-cardinality limits |
| Tuned bucket views: `*_time_in_state` (1 s–2 h), `*_handler_latency_in_state` (10 ms–60 s) | `crates/api/src/metrics.rs` | fleet-wide dwell/latency percentiles that actually resolve (defaults stopped at ~10 s) |
| `carbide_machine_created_to_ready_duration_seconds` histogram | post-commit `StateChangeHook` (`crates/api-core/src/created_to_ready_hook.rs`) | end-to-end ingestion time per machine; can't record rolled-back transitions |
| `StateChangeEvent.previous_state` available in production | state-controller | lets post-commit hooks act on the transition edge |

Pre-existing channels the toolkit exploits: the `machine_state_history` table
(every state write, timestamped — the ground truth) and the opt-in per-object
state endpoint (`[observability.per_object_state_metrics]`, port 9091).

## The three-channel design

```
every committed transition
  ├─ Postgres machine_state_history   → per-machine truth (S1)
  ├─ Loki  ← state_transition_committed → per-machine events (S2)
  └─ Prometheus histograms/counters     → fleet distributions (S3)
```

Same events, three independent pipelines. `combine-stage-stats.py` joins them
into ONE CSV per run (`stage-stats.csv`) whose `flags` column is a computed
disagreement test — **an empty flags column means all three channels
independently told the same story**. Nothing is interpreted by hand (or by an
LLM) on the way from cluster to CSV/PNG.

## Scripts

| Script | Role |
|---|---|
| `lib-env.sh` | shared env: runs dir, psql/Prometheus/Loki endpoint discovery + overrides |
| `sql-stage-timeline.sh <run> <from> <to>` | S1: per-machine timeline from `machine_state_history` (window REQUIRED — see gotcha 2) |
| `loki-stage-timeline.py <run> <from> <to>` | S2: `state_transition_committed` events (machine controller only) |
| `prom-stage-aggregates.sh <run> <from> <to>` | S3: dwell quantiles, entered counts, created→ready (see gotcha 3) |
| `report.py <run>` | REPORT.md: per-stage + per-machine tables, SQL↔Loki cross-check verdict |
| `combine-stage-stats.py <run>` | the single combined CSV with flags; re-attributes renamed machine ids |
| `plot-stage-stats.py <run> [<run> …]` | PNGs: per-machine gantt, stage totals, dwell ranges, multi-run comparison |
| `collect-run.sh <run> <from> <to> [compare …]` | runs all of the above for one run |
| `run-ingest-benchmark.sh <run> [hosts] [dpus]` | full benchmark against an installed cluster: MAT cleanup → ingest → wait for all-ready → collect |
| `run-full-benchmark-k8s.sh <run> [hosts] [dpus]` | reinstall-per-run on a real cluster: `clean.sh` → `setup.sh --with-observability` → `run-ingest-benchmark.sh`; manages collection port-forwards; `BENCH_KUBE_CONTEXT` safety latch (see header) |

The multi-node knob campaign built on these scripts — run plan, knob values,
and live progress tracker — is in [CAMPAIGN.md](CAMPAIGN.md).

Requirements: `kubectl` (context pointing at the cluster), `jq`, `python3`
(+ `matplotlib` for the plots: `pip3 install --user matplotlib`).

Quick start on an installed cluster:

```bash
export BENCH_RUNS_DIR=~/stage-timing-runs        # optional (this is the default)
./run-ingest-benchmark.sh smoke-5x2 5 2
column -t -s, ~/stage-timing-runs/smoke-5x2/stage-stats.csv | less -S
```

## Prerequisites on the cluster (will silently produce empty data if missed)

1. **The instrumented core image** — a build of this branch (the log line,
   views, and created→ready hook are in the code, not config).
2. **Observability stack installed** (`../../observability/install-observability.sh`
   or `setup.sh --with-observability`) — Prometheus `obs-prometheus.monitoring:9090`,
   Loki `loki.loki:3100`.
3. **NICo ServiceMonitors enabled** — they default OFF; without the
   `values-nico-servicemonitors.yaml` overlay Prometheus scrapes no `carbide_*`
   metrics at all (S3 comes back empty). `setup.sh --with-observability`
   applies it automatically; standalone installs print the command.
4. **Per-object endpoint (optional)** — site config
   `[observability.per_object_state_metrics] enabled = true` for live
   where-is-machine-X inspection on :9091.
5. **machine-a-tron in single-IP mode needs** `allow_insecure_discovery = true`
   in the site config (documented upstream as intended for exactly this), or
   every simulated DPU check-in is rejected on the source-IP guard and the
   whole fleet wedges in `dpuinit` forever. Not needed when agents check in
   from their real allocated IPs.

## Gotchas that cost us real debugging time (all field-verified)

1. **Run scripts where the endpoints are reachable.** Discovery returns
   ClusterIPs; from a workstation, port-forward and set `PROM_URL`/`LOKI_URL`
   (see lib-env.sh header).
2. **Always window-filter SQL extraction.** MAT machine ids are
   deterministic: a re-created fleet inherits the previous fleet's
   `machine_state_history` rows (cleanup does not truncate history). An
   unwindowed timeline silently mixes runs.
3. **S3 uses absolute counter values, not `increase()`** — correct only
   because `cleanup-machine-a-tron.sh` restarts nico-api (counters start at
   zero for the run). Two consequences: keep that restart in your protocol,
   and know that `increase()` would silently drop any burst that finishes
   before Prometheus's first scrape of the fresh pod (it did, in testing).
4. **History ≥ log, by design.** `machine_state_history` records every
   `controller_state` write, including out-of-band writers (site-explorer
   creation, discovery handlers); the log records only controller-committed
   transitions. Cross-check semantics are Loki ⊆ SQL (±2 s), never equality.
5. **Machines are renamed mid-ingest** (expected-machine adoption): history
   is migrated to the new id, already-shipped log lines keep the old one.
   `combine-stage-stats.py` re-attributes old→new by timestamp matching;
   raw `timeline-loki.csv` has pre-rename ids.
6. **Two state-name vocabularies**: DB serde tags (`dpudiscoveringstate`,
   `hostinit`) vs metric names (`dpudiscovering`, `hostnotready`). The
   combiner normalizes; substates additionally differ in shape (SQL has
   compound per-DPU labels, metrics carry the least-progressed DPU) so
   cross-channel validation happens at state level.
7. **Prometheus quantiles are bucket-interpolated** (e.g. a created→ready p50
   between the 600/1200 buckets reads "900"). Exact numbers come from the
   SQL timelines; Prometheus is for fleet-shape and dashboards.
8. **DPU machine rows mirror their host's state.** All scripts count host
   machines only; a "5×2" run is 5 machines in the CSVs, 15 in the DB.

## What to expect (validated baselines from the dev rig, default knobs)

- Per-machine ingest ≈ 15–16 min, dominated by `hostinit` (~60 %) and a
  ~144 s `waitingforcleanup` latch hit twice per machine (~30 %); handler
  execution cost is ≤100 ms p99 — machines wait, the controller is cheap.
- Wall clock is nearly flat with fleet size at small scale (15→150 machines:
  17→21 min) — but the ~2.3 s controller dispatch quantum stretches with
  fleet size (≈11 s at 150 machines; `state_controller.max_concurrency=10`
  is the suspected knob) and per-host cost starts rising (+27 % at 150).
- Every host walks `dpudiscovering` twice (preliminary identity + adopted
  identity — the rename above). Real duplicated work, visible only in S2.
- Knob saturation math (defaults): `machines_created_per_run=4`/30 s caps
  creation at ~8 machines/min; `concurrent_explorations=30` ≈ 10 hosts;
  `explorations_per_run=90` ≈ 30 hosts. On a 3-node cluster with different
  knob profiles, recompute before choosing fleet sizes.

## Full reinstall-per-run on a real cluster

Recycled clusters are a known confounder for ingestion benchmarks, so the
highest-fidelity protocol is a fresh install per run. `run-full-benchmark-k8s.sh`
wraps the whole cycle for any helm-prereqs-installable cluster:

```bash
export BENCH_KUBE_CONTEXT="$(kubectl config current-context)"   # destruction latch
export NICO_IMAGE_REGISTRY=<registry>/<org>/carbide-dev
export NICO_CORE_IMAGE_TAG=<instrumented Core tag>
export MAT_IMAGE_TAG=<machine-a-tron tag>
export REGISTRY_PULL_SECRET=<registry key>
export CORE_VALUES=/path/to/site-core-values.yaml     # must set allow_insecure_discovery=true
export METALLB_CONFIG=/path/to/site-metallb.yaml      # if the site uses MetalLB
./run-full-benchmark-k8s.sh baseline-100x2-r1 100 2
```

It refuses to run unless `BENCH_KUBE_CONTEXT` matches the current kubectl
context (`clean.sh` destroys the full NICo footprint). By default it installs
lean (`--skip-rest --skip-flow` — the benchmark never talks to REST);
`WITH_REST=true` restores the full stack. `SKIP_INSTALL=true` degrades it to
`run-ingest-benchmark.sh` plus managed port-forwards, for quick iteration on
an already-installed cluster.

## Differences from the k3s rig this was validated on

- The dev rig recreated the whole (single-node) cluster per run; on a real
  cluster, `run-full-benchmark-k8s.sh` is the equivalent reinstall-per-run
  protocol, and `run-ingest-benchmark.sh` alone is the quick warm-cluster
  variant. Keep runs comparable by keeping the cleanup(+nico-api restart)
  step.
- Storage for Prometheus/Loki here is node-pinned local-path — fine on 3
  nodes, but each store lives on one node; a node loss loses that history
  (extract per run, promptly, as this toolkit does).
- The dev rig's numbers above came from one 72-CPU box; absolute stage
  dwells (especially reboot/poll windows) will differ on real hardware — the
  method (three-channel validation, per-host-cost scaling) is what ports.

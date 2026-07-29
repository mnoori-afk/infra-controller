> Snapshot from the k3s dev-rig campaign, taken 2026-07-29 ~16:20Z.
> Ladder complete through 501 machines (scale-167x2); the 999-machine
> rung (scale-333x2) was still ingesting — live originals on the dev box.

# Findings — state-machine stage timing (living document)

## TL;DR

- Each machine takes ~15–16 min to ingest, and that number doesn't change
  from 15 to 75 machines — the system isn't overloaded, machines are just
  **waiting on fixed timers**.
- The time goes to two places: **hostinit (~60%)** and a **~2.4-min cleanup
  wait every machine hits twice (~30%)**. Everything else is seconds.
- Every quick step costs ~2.3 s at small scale — the controller's polling
  tick, pure scheduling overhead (~30 s per machine total). This tick
  stretches with fleet size (≈4.5 s at 75 machines, ≈11 s at 150): the first
  real queueing signal.
- Each host does its **discovery phase twice** (it gets renamed mid-ingest
  and starts over). Double work, by design.
- First crack at 150 machines: the fleet stops moving in lock-step — likely
  the controller's 10-at-a-time processing limit.
- At 300 machines the per-machine floor finally broke: 15–16 min → ~25 min
  per machine, all of it scheduling delay. The /24 address-pool worry did
  NOT materialize at 300 endpoints. Still predicted for the bigger runs:
  creation waves become the bottleneck (default = 4 machines per 30 s →
  ~2 h just to create 999).
- To make it faster, in order: (1) analyze which exact waits burn the time —
  no new runs needed; (2) raise `machines_created_per_run`; (3) raise
  controller concurrency; (4) tune exploration knobs; (5) the fail-fast lock
  fix; (6) stop the double discovery walk.

---

Updated 2026-07-29 ~14:10Z, mid-ladder (5→999-machine sweep in progress).
Every number below is script-computed and three-way cross-validated
(see DATA-DICTIONARY.md, VALIDATION-CAMPAIGN.md); interpretation and
hypotheses are marked as such.

## 1. Validated observations

**O1 — Ingestion on this box is latency-bound, not throughput-bound, up to
at least 75 machines.** Wall clock to all-ready: 17 min (15 machines), 17 min
(30), 19 min (75), and `created_to_ready` p50 = 900 s at every scale so far.
Per-host stage costs are flat across rungs; visit counts scale exactly
linearly. (Runs: fresh-5x2-r2, scale-10x2, scale-25x2.)

**O2 — The per-machine time budget is dominated by two stages.** From every
run's stage totals: `hostinit` ≈ 60–65 % of accounted time, `waitingforcleanup`
≈ 30 % (a near-constant ~144 s latch per visit, 2 visits per machine), DPU
stages and validation are single-digit percentages. The dwell distributions
are bimodal: most visits ~2.3 s (one controller cadence), a few long visits
(64–320 s) carry all the real time — i.e. a handful of wait-substates, not
uniform slowness. Handler execution cost is ≤ ~100 ms p99 everywhere:
machines *wait* in stages; the controller itself is cheap so far.

**O3 — The ~2.3 s quantum.** Median dwell for nearly every non-wait stage is
2.2–2.5 s at every scale — the state processor's dispatch cadence (2 s
`processor_dispatch_interval` + jitter), not work. Fast transitions cost one
scheduling tick each; ~14 ticks per machine ≈ 30 s of pure cadence overhead
per machine.

**O4 — First scaling signature at 150 machines: cohort spread.** Up to 75
machines the whole fleet moved through stages in lock-step. At 150 (scale-50x2,
mid-run observation) the cohort split — 45 machines a full stage ahead of the
trailing 105. First visible rationing of walk progress across the fleet.

**O5 — Machines are renamed mid-ingest (expected-machine adoption), and every
host walks `dpudiscovering` twice** — once under its preliminary identity,
once after adoption; the DB migrates history to the new id, so only the log
channel sees the first walk. Duplicated exploration/discovery work per host,
by design. (Fix log #8.)

**O6 — The DiscoverMachine source-IP guard rejects 100 % of MAT single-IP
check-ins** (~90 rejections/min from just 10 DPUs), permanently wedging
fleets in `dpuinit`. Unblocked via the documented `allow_insecure_discovery`
test knob. The rejection traffic we watched live is the same population as
wave-1's #1 finding (advisory-lock storm from rejected check-ins).
**Caveat this creates:** with the knob on, the rejected-check-in path is
*bypassed* on this rig — the wave-1 lock storm will under-reproduce here.
Lock pressure from *accepted* check-ins still exists and is measurable via
`carbide_network_segment_lock_wait_milliseconds`.

**O7 — created_to_ready p50 = "900 s" is bucket interpolation.** The
histogram buckets are 600/1200 s; a p50 landing between them interpolates to
~900. True medians (SQL) are 15–16 min. Treat Prometheus quantiles as
bucket-resolution; exact numbers come from the SQL timelines.

## Ladder updates (agent-maintained)

- **2026-07-29 14:15Z, scale-50x2 (150 machines) complete — ALL-READY in
  21 min, cross-check PASS, zero unexplained flags.** Wall clock is still
  near-flat (17/17/19/21 min for 15/30/75/150), so H1's fixed-timer floor
  still dominates.
- **2026-07-29, rungs 25x2+50x2: the ~2.3 s dispatch quantum (O3) is NOT
  scale-invariant.** Median dwell of every controller-polled stage rose
  uniformly: ~2.4 s (≤30 machines) → ~4.4–5.2 s (75) → ~11.1–11.3 s (150) —
  even one-visit stages like bomvalidating/validation. Uniformity across all
  stages says controller-service-rate queueing, not any stage's handler —
  **supports H2** (state_controller.max_concurrency=10); confirm via T3
  (raise SCALE_STATE_CONTROLLER_MAX_CONCURRENCY and watch the quantum drop
  back to ~2.3 s).
- **2026-07-29: per-host dwell cost is no longer flat (refines O1):** total
  926 → 927 → 1040 → 1175 s/host at 5/10/25/50 hosts (+27% at 150 machines).
  Fastest-diverging stage is dpudiscoveringstate (26 → 24 → 62 → 113 s/host,
  4.3×) because it has the most visits per host (11) and each visit pays the
  stretched quantum. Knobs: max_concurrency first;
  concurrent_explorations=30 may add to it beyond 30 hosts.
- **2026-07-29: waitingforcleanup per-host cost FELL at 150 machines
  (289 → 287 → 230 s/host, p50 145 → 108 s):** the fixed cleanup latch
  overlaps the now-slower walk, so slower scheduling eats part of the timer
  instead of adding to it — consistent with H1's fixed-latency-chain model.
- **2026-07-29 14:57Z, scale-100x2 (300 machines) complete — ALL-READY in
  26 min, PASS, no unexplained flags. Kills H5:** all 300 machines created
  and ready, no pool-exhaustion/allocation errors — the /24s are not the
  binding limit at 300 endpoints (T7 unnecessary at this scale; 333x2 =
  999 endpoints will still exceed a /24 if allocation is one-IP-per-machine,
  so keep watching there).
- **2026-07-29, scale-100x2: the per-machine time floor broke for the first
  time** — created_to_ready p50 jumped 900 → 1500 s (bucket-interp.) and the
  dispatch quantum hit ~23 s/visit. The quantum is now cleanly linear in
  fleet size (2.4/2.4/4.9/11.3/23 s at 15/30/75/150/300 machines — doubles
  with each fleet doubling). Strengthens H2 (max_concurrency=10); the knee
  is at ~75 machines, NOT at ~30 hosts as the exploration-knob predictions
  suggested. The cleanup-latch slack is nearly used up (p50 63 s of ~144 s),
  so 167x2/333x2 wall clocks should start rising steeply even before
  creation waves (H3) bind.
- **2026-07-29 15:56Z, scale-167x2 (501 machines) complete — ALL-READY in
  40 min, PASS, no unexplained flags. Wall clock finally bent** (26 → 40 min
  for 300 → 501 machines); created_to_ready p50 = ~2672 s (~45 min/machine,
  3× the small-fleet floor). Quantum ~36–39 s/visit, still linear in fleet
  size — H2's max_concurrency=10 story holds; T3 remains the top knob test.
- **2026-07-29, scale-167x2 weakens H3 badly:** all 501 machines were
  created within ~17 min of ingest start — nowhere near the ~60 min that
  machines_created_per_run=4 per 30 s predicts. Either the knob's effective
  cycle is much faster on this rig or creation isn't serialized as modeled;
  333x2 (999 machines) is the remaining test before calling H3 dead.
  Raising machines_created_per_run (T2) may therefore buy little.

## 2. Hypotheses (cause → observable that would confirm)

**H1 — The ~900–960 s floor is a fixed-latency chain, not load.** Sum of
mandatory waits (2 × ~144 s cleanup latch + hostinit reboot/poll windows +
N × 2.3 s cadence ticks) ≈ the observed floor at every scale. → Confirm by
decomposing `hostinit` substate dwells from timeline-sql.csv (which
substates hold the 64–320 s visits) — analysis-only, no new runs needed.

**H2 — Cohort spread at 150 machines is `state_controller.max_concurrency=10`
rationing.** 150 machines × ~2.3 s min service time ÷ 10 concurrent ≈ the
lag observed between leading/trailing sub-cohorts. → Confirm if spread
widens proportionally at 300/501/999; kill test = raising
`SCALE_STATE_CONTROLLER_MAX_CONCURRENCY` (E6) and watching the spread close.

**H3 — Creation waves become the dominant cost at ≥~300 machines.** Default
`machines_created_per_run=4` per 30 s cycle caps creation at ~8 machines/min;
501 machines ⇒ ~60 min just to create, 999 ⇒ ~2 h. Up to 150 machines this
was masked by exploration running concurrently. → The 167x2/333x2 rungs
should show `created`→first-transition timestamps spreading across hours and
per-host dpudiscovering *entry* times staggering, while post-creation stage
dwells stay flat.

**H4 — Exploration-cycle compounding (the epic's core mechanism) engages
between 150 and 300 machines** (`explorations_per_run=90` vs 450+ endpoints,
sweeps no longer fit a cycle; also `concurrent_explorations=30`). → Watch
`explore_cycle` behavior and whether preliminary-identity dpudiscovering
dwell grows with fleet size while post-adoption stages don't.

**H5 — /24 address-pool exhaustion at ≥~254 endpoints (UNTESTED, answered by
scale-100x2).** The dev values give OOB/admin /24 prefixes; 300 endpoints may
exhaust allocation. Failure signature: pool-exhaustion / DHCP allocation
errors in mat.log or nico-api logs. Fix if hit: widen prefixes in
values-dev-k3s (local, one line).

## 3. What to test next, ranked by expected payoff

| # | Experiment | Tests | How |
|---|---|---|---|
| T1 | **Decompose hostinit + cleanup fixed waits** (no new runs — analyze existing timelines at substate level) | H1: where exactly do the 64–320 s visits live; is the 144 s cleanup latch a timer we can shrink | python over timeline-sql.csv of any completed run |
| T2 | **machines_created_per_run 4→40→100 at 167x2** (E2) | H3: creation-wave ceiling — predicted to be the single biggest wall-clock lever at scale | cherry-pick #3757 (`a55190a32`) onto the timing branch for `SCALE_MACHINES_CREATED_PER_RUN`, rebuild image, one pipeline run per value |
| T3 | **state_controller.max_concurrency 10→50→100 at 150+ machines** (E6) | H2: cohort spread / walk rationing | same cherry-pick (`SCALE_STATE_CONTROLLER_MAX_CONCURRENCY`) |
| T4 | **explorations_per_run & concurrent_explorations sweeps at 333x2** (E3/E4) | H4: cycle economics; wave-1 predicted E2>E3/E4 — verify on this box | `SCALE_EXPLORATIONS_PER_RUN`, `SCALE_CONCURRENT_EXPLORATIONS` |
| T5 | **Fail-fast-before-lock code fix** (wave-1 #1, `machine_discovery.rs` — move the reject checks before `lock_all_admin_segments`) at 333x2, before/after | the top code-level bottleneck; measure `carbide_network_segment_lock_wait_milliseconds` + stage dwells | implement on the timing branch, rebuild, pipeline run; note O6 caveat — to reproduce the storm properly may require re-enabling the source-IP guard |
| T6 | **Eliminate the double dpudiscovering walk** (O5) — investigate whether adoption can precede exploration or reuse the preliminary walk's results | O5: ~2× discovery cost per host | code reading first (`machine_creator.rs` adoption path), then a targeted fix |
| T7 | **Widen /24 pools** (only if H5 bites at scale-100x2) | H5 | one-line values change + rerun affected rungs |

## 4. Status of the evidence base

Completed & fully validated: fresh-5x2-r2 (anchor), scale-10x2, scale-25x2.
In flight: scale-50x2 (cohort-spread observation is preliminary until its
REPORT lands), then scale-100x2, scale-167x2 (501 machines), scale-333x2
(999 machines). The analysis agent maintains LADDER-ANALYSIS.md (per-rung
tables + final per-host-cost divergence matrix); this file holds the
interpretation and the test queue. Raw artifacts: `runs/<run>/`, column
definitions: DATA-DICTIONARY.md.

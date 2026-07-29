> Snapshot from the k3s dev-rig campaign, taken 2026-07-29 ~16:20Z.
> Ladder complete through 501 machines (scale-167x2); the 999-machine
> rung (scale-333x2) was still ingesting — live originals on the dev box.

# Scale-ladder analysis — 10x2 / 25x2 / 50x2 / 100x2

Campaign of 2026-07-29 (see `runs/ladder.log`). Each rung is a fully fresh
cluster (`just clean` → stack install → MAT scale ingest → extraction) via
`run-full-benchmark.sh`; methodology and validation in `VALIDATION-CAMPAIGN.md`.

Method per rung, from `runs/scale-<N>x2/stage-stats.csv` `substate="*"` rows
(SQL ground truth, cross-validated against Loki + Prometheus via `flags`):

- **dwell_sum_s** — total seconds all machines spent in the stage.
- **per_host_s = dwell_sum_s ÷ hosts** — the scaling detector: a stage that
  scales linearly has a flat per-host cost across rungs; a superlinear
  (saturating) stage's per-host cost rises with fleet size.
- **dwell_p50_s** — median dwell per visit (exact, from SQL).
- `created_to_ready_p50_s` / `_count` from `stage-aggregates.csv` (Prometheus).
- Ingest wall-clock from `pipeline.log` "PHASE 5 ingest DONE ... after Xmin".

Linear reference anchor: **fresh-5x2-r2** — 5 hosts, 17 min ingest,
total per-host dwell 925.8 s, created_to_ready p50 = 900 s.

Predicted saturation points (from the epic / VALIDATION-CAMPAIGN.md):
`machines_created_per_run=4` (creation waves), `concurrent_explorations=30`
(~10 hosts), `explorations_per_run=90` (~30 hosts), state_controller
`max_concurrency=10`.

---

## Rung 1 — scale-10x2 (10 hosts, 20 DPUs) — COMPLETE, data trustworthy

- Pipeline: COMPLETE (13:05:09Z). Cross-check verdict: **PASS**.
- Flags: only `SQL_OPEN(10)` on `ready` (expected end-of-run condition). All
  other state-level rows flag-free → all three sources agree.
- Ingest wall-clock: **17 min** (verdict ALL-READY) — same as 5x2.
- `created_to_ready`: p50 = **900 s**, p95 = 1170 s, count = **10** (= hosts).

| state | n_sql | dwell_sum_s | per_host_s | dwell_p50_s | 5x2 per_host_s |
|---|---|---|---|---|---|
| bomvalidating | 10 | 21.9 | 2.2 | 2.15 | 2.4 |
| created | 10 | 0.0 | 0.0 | 0.00 | 0.0 |
| dpudiscoveringstate | 110 | 237.2 | 23.7 | 2.34 | 26.2 |
| dpuinit | 60 | 1543.0 | 154.3 | 2.48 | 163.3 |
| hostinit | 210 | 4550.2 | 455.0 | 2.36 | 442.1 |
| validation | 10 | 23.6 | 2.4 | 2.39 | 2.4 |
| waitingforcleanup | 20 | 2894.5 | 289.4 | 144.72 | 289.4 |
| **TOTAL** | | **9270.4** | **927.0** | | **925.8** |

Verdict at this rung: **fully linear vs the 5x2 anchor** (total per-host cost
927.0 vs 925.8 s, +0.1%; every stage within ±10%; identical wall-clock and
created_to_ready p50). Visit counts scale exactly 2× (110/60/210/10/10/20 vs
55/30/105/5/5/10). No sign yet of the `concurrent_explorations=30` (~10 hosts)
saturation prediction.

---

## Rung 2 — scale-25x2 (25 hosts, 50 DPUs) — COMPLETE, data trustworthy

- Pipeline: COMPLETE (13:39:31Z). Cross-check verdict: **PASS**.
- Flags: only `SQL_OPEN(25)` on `ready` (expected). All other rows flag-free.
- Ingest wall-clock: **19 min** (ALL-READY) vs 17 min at 5 and 10 hosts.
- `created_to_ready`: p50 = **900 s**, p95 = 1170 s, count = **25** (= hosts).
  (Histogram-bucket-interpolated; identical value likely means same bucket.)

| state | n_sql | dwell_sum_s | per_host_s | dwell_p50_s | 10x2 per_host_s | 5x2 per_host_s |
|---|---|---|---|---|---|---|
| bomvalidating | 25 | 62.5 | 2.5 | 2.37 | 2.2 | 2.4 |
| created | 25 | 0.0 | 0.0 | 0.00 | 0.0 | 0.0 |
| dpudiscoveringstate | 275 | 1544.0 | **61.8** | **5.15** | 23.7 | 26.2 |
| dpuinit | 150 | 4464.8 | 178.6 | 4.90 | 154.3 | 163.3 |
| hostinit | 525 | 12718.0 | 508.7 | 4.41 | 455.0 | 442.1 |
| validation | 25 | 56.5 | 2.3 | 2.21 | 2.4 | 2.4 |
| waitingforcleanup | 50 | 7164.3 | 286.6 | 137.71 | 289.4 | 289.4 |
| **TOTAL** | | **26010.0** | **1040.4** | | **927.0** | **925.8** |

Observations at this rung (factual):

- Total per-host dwell rose **927 → 1040 s (+12%)**; wall-clock 17 → 19 min.
- **First divergence: `dpudiscoveringstate`** — per-host cost **23.7 → 61.8 s
  (2.6×)**, median dwell per visit 2.34 → 5.15 s. Visit counts still scale
  exactly linearly (275 = 11×25), so the growth is per-visit dwell, not extra
  visits.
- Median dwell of all controller-polled stages roughly doubled (≈2.4 s →
  4.4–5.2 s in dpudiscovering/dpuinit/hostinit), consistent with slower
  controller service rate per machine at 25 hosts (max_concurrency=10 <
  25 machines). Timer-dominated stages stayed flat (waitingforcleanup
  per-host 286.6 ≈ 289; bomvalidating/validation ≈ 2.4 s).

---

## Rung 3 — scale-50x2 (50 hosts, 100 DPUs) — COMPLETE, data trustworthy

- Pipeline: COMPLETE (14:14:41Z). Cross-check verdict: **PASS**.
- Flags: only `SQL_OPEN(50)` on `ready` (expected). All other rows flag-free.
- Ingest wall-clock: **21 min** (ALL-READY). Ladder so far: 17 / 17 / 19 / 21.
- `created_to_ready`: p50 = **900 s**, p95 = 1170 s, count = **50** (= hosts).

| state | n_sql | dwell_sum_s | per_host_s | dwell_p50_s | 25x2 per_host_s | 10x2 | 5x2 |
|---|---|---|---|---|---|---|---|
| bomvalidating | 50 | 352.8 | 7.1 | 6.97 | 2.5 | 2.2 | 2.4 |
| created | 50 | 0.0 | 0.0 | 0.00 | 0.0 | 0.0 | 0.0 |
| dpudiscoveringstate | 550 | 5664.6 | **113.3** | **11.10** | 61.8 | 23.7 | 26.2 |
| dpuinit | 300 | 9456.9 | 189.1 | 11.30 | 178.6 | 154.3 | 163.3 |
| hostinit | 1050 | 31459.6 | **629.2** | **11.30** | 508.7 | 455.0 | 442.1 |
| validation | 50 | 335.4 | 6.7 | 7.12 | 2.3 | 2.4 | 2.4 |
| waitingforcleanup | 100 | 11490.6 | 229.8 | 108.37 | 286.6 | 289.4 | 289.4 |
| **TOTAL** | | **58759.8** | **1175.2** | | **1040.4** | **927.0** | **925.8** |

Observations at this rung (factual):

- Total per-host dwell **1040 → 1175 s (+27% vs anchor)**; wall-clock 21 min.
- Visit counts remain exactly linear (550/300/1050 = 11/6/21 per host).
- Median per-visit dwell of every controller-polled stage rose again, and
  uniformly: ≈2.4 s (5–10 hosts) → ≈4.4–5.2 s (25) → **≈11.1–11.3 s (50)**,
  including the one-visit stages bomvalidating (6.97) and validation (7.12).
  This is queueing on the state controller, not any single stage's handler.
- `dpudiscoveringstate` remains the fastest-diverging stage by per-host cost
  (26 → 24 → 62 → 113 s; 4.3× the anchor) — it has the most visits per host
  (11) so it amplifies the per-iteration queueing delay the most.
- `waitingforcleanup` per-host cost *fell* (289 → 287 → 230 s) and its p50
  fell (145 → 138 → 108 s): a timer-driven wait that overlaps with the slower
  polling, so slower iterations consume part of the fixed wait.

---

## Rung 4 — scale-100x2 (100 hosts, 200 DPUs) — COMPLETE, data trustworthy

- Pipeline: COMPLETE (14:56:53Z). Cross-check verdict: **PASS**.
- Flags: only `SQL_OPEN(100)` on `ready` (expected). All other rows flag-free.
- Ingest wall-clock: **26 min** (ALL-READY). Ladder: 17 / 17 / 19 / 21 / 26.
- `created_to_ready`: p50 = **1500 s** (up from 900 s at all smaller rungs),
  p95 = 1770 s, count = **100** (= hosts).
- **No /24 pool exhaustion**: all 300 machines were created and reached ready;
  no allocation failures observed (mid-run state counts moved steadily).

| state | n_sql | dwell_sum_s | per_host_s | dwell_p50_s |
|---|---|---|---|---|
| bomvalidating | 100 | 1640.7 | 16.4 | 13.86 |
| created | 100 | 0.0 | 0.0 | 0.00 |
| dpudiscoveringstate | 1100 | 21784.5 | **217.8** | **22.62** |
| dpuinit | 600 | 23924.5 | 239.2 | 23.00 |
| hostinit | 2100 | 83449.8 | **834.5** | **23.35** |
| validation | 100 | 1748.1 | 17.5 | 19.18 |
| waitingforcleanup | 200 | 13741.9 | 137.4 | 63.07 |
| **TOTAL** | | **146289.4** | **1462.9** | |

Observations at this rung (factual):

- Visit counts still exactly linear (1100/600/2100 = 11/6/21 per host).
- The dispatch quantum doubled again: median per-visit dwell ≈ **23 s** on
  every controller-polled stage (2.4 → 2.4 → ~4.9 → ~11.3 → ~23 s across the
  ladder — doubling each time the fleet doubles, i.e. per-visit service delay
  is now linear in fleet size).
- `created_to_ready` p50 left the 600–1200 s histogram bucket for the first
  time (900 → 1500 s interpolated).
- `waitingforcleanup` continued to shrink (per-host 137.4 s, p50 63 s): the
  fixed latch is increasingly absorbed by walk slowness.

---

# Interim (rungs 1–4) — divergence analysis

## Per-host dwell cost matrix (dwell_sum_s ÷ hosts, s) — flat row = linear

| state | 5x2 | 10x2 | 25x2 | 50x2 | 100x2 | 100x2 / 5x2 |
|---|---|---|---|---|---|---|
| bomvalidating | 2.4 | 2.2 | 2.5 | 7.1 | 16.4 | 6.9× |
| dpudiscoveringstate | 26.2 | 23.7 | 61.8 | 113.3 | 217.8 | **8.3×** |
| dpuinit | 163.3 | 154.3 | 178.6 | 189.1 | 239.2 | 1.5× |
| hostinit | 442.1 | 455.0 | 508.7 | 629.2 | 834.5 | 1.9× |
| validation | 2.4 | 2.4 | 2.3 | 6.7 | 17.5 | 7.3× |
| waitingforcleanup | 289.4 | 289.4 | 286.6 | 229.8 | 137.4 | **0.47×** |
| **TOTAL** | **925.8** | **927.0** | **1040.4** | **1175.2** | **1462.9** | **1.58×** |

## End-to-end scaling

| metric | 5x2 | 10x2 | 25x2 | 50x2 | 100x2 |
|---|---|---|---|---|---|
| machines (hosts×3) | 15 | 30 | 75 | 150 | 300 |
| ingest wall-clock (min) | 17 | 17 | 19 | 21 | 26 |
| created_to_ready_p50_s (Prom, bucket-interp.) | 900 | 900 | 900 | 900 | 1500 |
| created_to_ready_count (= hosts?) | 5 ✓ | 10 ✓ | 25 ✓ | 50 ✓ | 100 ✓ |
| total per-host dwell (s) | 926 | 927 | 1040 | 1175 | 1463 |
| median per-visit dwell, polled stages (s) | ~2.4 | ~2.4 | ~4.9 | ~11.3 | ~23 |

## Verdict: which stage diverges, and where

1. **The divergence is controller-wide queueing, not one stage's work.** From
   the 25x2 rung (75 machines) onward, the median dwell of *every*
   controller-polled visit grows, and it grows uniformly (~4.9 → ~11.3 →
   ~23 s as the fleet doubles twice). Per-visit service delay is linear in
   fleet size above ~30 machines. Handler cost stayed cheap in prior runs,
   and visit counts are exactly linear at every rung — so this is the state
   controller serving N machines with bounded concurrency
   (`state_controller max_concurrency=10`), each visit paying a queue-length
   delay.
2. **First stage to diverge: `dpudiscoveringstate`, at the 25x2 rung** —
   per-host cost 24 → 62 s (2.6×) while everything else moved ≤12%. It is
   the most visit-heavy stage (11 visits/host, incl. the double discovery
   walk), so it amplifies the queueing delay ~11× per host. By 100x2 it costs
   8.3× the anchor per host. `hostinit` (21 visits/host but dominated by
   fixed waits) diverges in absolute terms the most: +392 s/host vs anchor.
3. **Wall clock is still timer-dominated** (26 min for 300 machines vs 17 min
   for 15 — only 1.5× for 20× the machines), because the growing queue delay
   partially hides inside the fixed waits: `waitingforcleanup` per-host cost
   fell from 289 to 137 s. That slack is nearly exhausted, though: p50 of the
   cleanup latch is down to 63 s from 145 s. Extrapolating the quantum
   (~46 s/visit at 600 machines, ~7 min of pure queueing per machine's ~14
   fast visits) predicts the knee becomes wall-clock-visible at the 167x2 and
   333x2 rungs.
4. **Against the predicted saturation points:** `concurrent_explorations=30`
   (~10 hosts) — no effect visible at 10 hosts; the first measurable knee is
   at 25 hosts (75 machines), consistent with `max_concurrency=10` rationing
   instead. `machines_created_per_run=4` creation waves did not bind through
   100 hosts (creation overlapped exploration; count always = hosts, wall
   clock near-flat). `explorations_per_run=90` (~30 hosts): plausibly part of
   the same 25→50 hosts slope, but the uniform cross-stage quantum growth
   points at the controller, not exploration cycles, as the primary driver.
   No pool exhaustion at 300 endpoints (H5 signature absent).

---

# Extension rungs (LADDER-EXT): scale-167x2, scale-333x2

## Rung 5 — scale-167x2 (167 hosts, 334 DPUs, 501 machines) — COMPLETE, data trustworthy

- Pipeline: COMPLETE (15:55:40Z). Cross-check verdict: **PASS**.
- Flags: only `SQL_OPEN(167)` on `ready` (expected). All other rows flag-free.
- Ingest wall-clock: **40 min** (ALL-READY). Ladder: 17/17/19/21/26/**40**.
- `created_to_ready`: p50 = **2672 s** (~45 min), p95 = 3507 s, count = **167**.
- Creation waves did NOT bind: all 501 machines existed in the DB within
  ~17 min of ingest start (predicted ~60 min at 4 per 30 s), and the fleet
  reached 501/501 ready by ~15:30Z; the remaining pipeline time was
  watcher/extraction.

| state | n_sql | dwell_sum_s | per_host_s | dwell_p50_s |
|---|---|---|---|---|
| bomvalidating | 167 | 5724.2 | 34.3 | 35.59 |
| created | 167 | 0.0 | 0.0 | 0.00 |
| dpudiscoveringstate | 1837 | 58211.2 | 348.6 | 36.74 |
| dpuinit | 1002 | 57357.6 | 343.5 | 39.00 |
| hostinit | 3507 | 190265.0 | 1139.3 | 38.16 |
| validation | 167 | 5852.3 | 35.0 | 35.57 |
| waitingforcleanup | 334 | 41155.2 | 246.4 | 39.99 |
| **TOTAL** | | **358565.5** | **2147.1** | |

Observations (factual):

- Visit counts still exactly linear (1837/1002/3507 = 11/6/21 per host).
- Dispatch quantum now ≈ **36–39 s**/visit (23 s at 300 machines; 501/300 =
  1.67×, quantum 1.6×) — the linear-in-fleet-size service delay continues.
- `waitingforcleanup` inverted again: p50 fell to 40 s (< one quantum — the
  fixed latch is now entirely hidden behind scheduling), but per-host cost
  rose back to 246 s because *exiting* the stage itself now waits on the
  queue.
- Total per-host dwell 1463 → 2147 s (+47% for 1.67× machines): the growth
  is now superlinear in wall-time terms — wall clock finally bent (26 → 40
  min).

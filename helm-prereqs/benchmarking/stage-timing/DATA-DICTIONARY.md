# Data dictionary — stage-timing CSVs

(Ported from the k3s dev-bench rig where this toolkit was validated; column
semantics are cluster-independent.)

Every benchmark run produces four CSVs under `$BENCH_RUNS_DIR/<run-name>/ (default ~/stage-timing-runs)`. This file
defines every column in plain English. General conventions first:

- **machine** = a *host* machine only. DPU rows in the database mirror their
  host's state and are excluded everywhere; a "5×2" run therefore has 5
  machines in these files, not 15.
- **stage** = a `(state, substate)` step of the machine state machine
  (e.g. `hostinit / waitingfordiscovery`). A machine *visits* a stage, dwells
  there, then transitions out. A stage can be visited more than once.
- **dwell** = wall-clock time spent inside one visit to a stage: from the
  transition that entered it to the transition that left it.
- Timestamps are UTC ISO-8601. Durations are seconds unless the column name
  says `_ms` (milliseconds).
- Two vocabularies exist for the same states: the **database** serde tags
  (`dpudiscoveringstate`, `dpuinit`, `hostinit`, …) and the **metrics/log**
  names (`dpudiscovering`, `dpunotready`, `hostnotready`, …). The combined
  CSV normalizes everything onto the database vocabulary.

---

## 1. `timeline-sql.csv` — per-machine timeline, ground truth (Postgres)

Source: the `machine_state_history` table — the rows the state machine itself
writes on every state change. One row = one visit of one machine to one stage.
Extraction is window-filtered (mandatory: machine ids are reused across runs).

| Column | Meaning |
|---|---|
| `machine_id` | The host machine's permanent identifier (`fm100…`). Note: machines are renamed once mid-ingest; this file always shows the **final** id (history is migrated to it). |
| `seq` | Visit order for this machine: 1 = first recorded state, counting up. Purely per-machine ordering. |
| `state` | The stage's top-level state, database vocabulary (`created`, `dpudiscoveringstate`, `dpuinit`, `hostinit`, `waitingforcleanup`, `bomvalidating`, `validation`, `ready`, …). |
| `substate` | The step within the state. For DPU states this aggregates the per-DPU map: `configuring+initializing` means one DPU was configuring while the other was still initializing. Empty for states with no substate (e.g. `created`, `ready`). |
| `entered_at` | When the machine entered this stage (the transition's DB timestamp). |
| `exited_at` | When it left (= the next row's `entered_at`). **Empty on each machine's last row** — it was still in that stage when we extracted. |
| `dwell_s` | `exited_at − entered_at`, seconds. Empty when `exited_at` is empty. |

## 2. `timeline-loki.csv` — per-machine transition events (log pipeline)

Source: the `state_transition_committed` log line our instrumentation emits at
the exact moment a transition commits, shipped to Loki. One row = one
committed transition **by the machine state controller** (writes made by other
components — e.g. site-explorer creating machines — appear in the SQL file but
not here; that asymmetry is expected).

| Column | Meaning |
|---|---|
| `machine_id` | Machine id **as logged at the time** — before the mid-ingest rename this is the machine's original id. The combiner re-attributes these to the final id automatically; use this file raw only with that caveat. |
| `ts` | When the transition committed (Loki event timestamp). |
| `from_state`, `from_substate` | The stage being left, metrics/log vocabulary. The controller's substate is the *least-progressed DPU* only (single label, not the compound SQL form). |
| `to_state`, `to_substate` | The stage being entered, same vocabulary. |
| `dwell_ms` | Milliseconds the machine spent in the `from_*` stage, as measured in-process by the controller. Should agree with the SQL `dwell_s` for the same visit to within ~1s. |

## 3. `stage-aggregates.csv` — fleet-wide statistics (Prometheus)

Source: PromQL queries over the instrumented histograms/counters. One row =
one statistic for one stage (long/narrow format: pivot on `metric`). Values
are **absolute since the run's start** — valid because cleanup restarts
nico-api, which zeroes all counters (do not reuse these queries on a
long-running cluster).

| Column | Meaning |
|---|---|
| `metric` | Which statistic this row is (see list below). |
| `state`, `substate` | The stage, metrics vocabulary. Empty for fleet-level metrics (created→ready rows). |
| `value` | The number. `NaN` = the histogram had no samples for that stage. |

`metric` values:

| Value | Meaning |
|---|---|
| `entered_total` | How many times any machine entered this stage (controller transitions only). |
| `dwell_p50_s` / `dwell_p95_s` / `dwell_p99_s` | Median / 95th / 99th percentile dwell per visit, estimated from histogram buckets — so values are interpolated between bucket bounds (coarser than the SQL numbers, by design). |
| `dwell_sum_s` | Total seconds all machines spent in this stage, summed. |
| `handler_p99_ms` | 99th percentile of the *handler execution cost* for this stage — how long the controller's code ran per iteration, **not** how long machines waited in the stage. High dwell + low handler = waiting; high handler = the stage itself is expensive. |
| `created_to_ready_p50_s` / `_p95_s` | Percentiles of end-to-end ingestion time (machine row created → entered `ready`), from the dedicated histogram. |
| `created_to_ready_count` | How many machines completed the full journey — should equal the host count of the run. |

## 4. `stage-stats.csv` — the combined, cross-validated view (from the 3 above)

Produced by `combine-stage-stats.py`. Two kinds of rows:

- **`substate = "*"` rows — the trustworthy summary.** One per state, with all
  three sources side by side and automatic disagreement flags. Read these.
- **substate rows — per-source detail.** SQL and Loki/Prom substates use
  different vocabularies (compound vs least-progressed), so these carry no
  cross-source flags; use them for drill-down within one source.

| Column | Meaning |
|---|---|
| `state` | Stage's state, database vocabulary (Loki/Prom names normalized onto it). |
| `substate` | `*` for the cross-validated state rollup; otherwise the source-specific substate label. |
| `n_sql` | Completed visits per the SQL ground truth (rows with a dwell). |
| `dwell_min_s` / `dwell_p50_s` / `dwell_p95_s` / `dwell_max_s` | Min / median / 95th percentile / max dwell per visit, computed exactly from SQL dwells. |
| `dwell_sum_s` | Total time all machines spent in the stage (SQL) — the "where did the run's time go" column, and the chart `stage-totals.png`. |
| `n_loki` | Committed transitions out of this stage per the log events, after re-attributing pre-rename ids to final ids. Should track `n_sql` (SQL may be slightly higher: it also sees non-controller writes). |
| `loki_p50_s` | Median dwell per the log events' `dwell_ms`. Should agree with `dwell_p50_s` within ~1s. |
| `prom_entered` | Times machines entered this stage per the Prometheus counter. Compared against Loki entries (by to-state). |
| `prom_p50_s` / `prom_p95_s` | Dwell percentiles per Prometheus (bucket-interpolated; only on substate rows, since the histogram's labels are substate-level). |
| `flags` | **Computed disagreement tests — empty means all sources agree.** `SQL_OPEN(n)` = n visits hadn't ended at extraction (expected for `ready` at end-of-run); `LOKI_MISSING` = SQL saw exits but no log events (a pipeline bug, except for `created`, which the controller never writes); `COUNT_DRIFT(sql=…/loki=…)` = visit counts diverge beyond the out-of-band allowance; `P50_DRIFT(sql=…/loki=…)` = medians differ >2s and >10%; `PROM_ABSENT` = no Prometheus series for a stage the others saw; `PROM_COUNT_DRIFT(prom=…/loki=…)` = entry counts diverge between counter and log. |

## 5. Small run files

| File | Meaning |
|---|---|
| `window-start.txt` / `window-end.txt` | The run's extraction window (UTC). Start is stamped just before machine-a-tron begins; end when the fleet reached ready (or the watcher gave up). All extractions filter to this window. |
| `mat.log`, `setup.log`, `obs.log`, `upgrade.log`, `cleanup.log` | Raw logs of the run's phases (machine-a-tron ingest; on fresh-cluster runs also stack install, observability install, image upgrade). |
| `plots/*.png`, `REPORT.md` | Script-rendered charts and the merged human-readable report incl. the cross-check verdict. |

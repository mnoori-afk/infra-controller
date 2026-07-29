#!/usr/bin/env bash
# S3 — per-stage aggregates from Prometheus for a run window.
# Usage: prom-stage-aggregates.sh <run-name> <from-iso> <to-iso>
# Writes runs/<run-name>/stage-aggregates.csv:
#   metric,state,substate,value
# Rows: entered counts, dwell p50/p95/p99 (s), handler p99 (ms),
# created→ready p50/p95 (s).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib-env.sh"

NAME="${1:?usage: prom-stage-aggregates.sh <run-name> <from> <to>}"
FROM="${2:?from-iso}"; TO="${3:?to-iso}"
OUT="$RUNS_DIR/$NAME/stage-aggregates.csv"
mkdir -p "$RUNS_DIR/$NAME"

PROM="$(prom_url)"
[[ -n "$PROM" ]] || { echo "ERROR: cannot resolve obs-prometheus" >&2; exit 1; }

END_S=$(iso_epoch "$TO")
START_S=$(iso_epoch "$FROM")
WINDOW="$(( END_S - START_S ))s"
# NOTE: queries use ABSOLUTE counter/bucket values, not increase(): the run
# protocol restarts nico-api during cleanup, so counters are zero at run
# start and their current value IS the per-run count. increase() silently
# drops any burst that lands before Prometheus's first scrape of the new pod
# (observed: a full 5x2 creation burst finished pre-first-scrape -> 0).

# instant query evaluated at the window end; emits csv rows "<metric>,state,substate,value"
q() { # q <metric-label> <promql>
    local tag="$1" promql="$2"
    curl -sf --max-time 60 "$PROM/api/v1/query" \
        --data-urlencode "query=$promql" --data-urlencode "time=$END_S" \
    | jq -r --arg tag "$tag" '
        .data.result[]
        | [$tag, (.metric.state // ""), (.metric.substate // ""),
           (.value[1])] | @csv'
}

{
echo 'metric,state,substate,value'
q "entered_total"  "sum by (state, substate) (carbide_machines_state_entered_total)"
q "dwell_p50_s"    "histogram_quantile(0.50, sum by (state, substate, le) (carbide_machines_time_in_state_seconds_bucket))"
q "dwell_p95_s"    "histogram_quantile(0.95, sum by (state, substate, le) (carbide_machines_time_in_state_seconds_bucket))"
q "dwell_p99_s"    "histogram_quantile(0.99, sum by (state, substate, le) (carbide_machines_time_in_state_seconds_bucket))"
q "dwell_sum_s"    "sum by (state, substate) (carbide_machines_time_in_state_seconds_sum)"
q "handler_p99_ms" "histogram_quantile(0.99, sum by (state, substate, le) (carbide_machines_handler_latency_in_state_milliseconds_bucket))"
q "created_to_ready_p50_s" "histogram_quantile(0.50, sum by (le) (carbide_machine_created_to_ready_duration_seconds_bucket))"
q "created_to_ready_p95_s" "histogram_quantile(0.95, sum by (le) (carbide_machine_created_to_ready_duration_seconds_bucket))"
q "created_to_ready_count" "sum(carbide_machine_created_to_ready_duration_seconds_count)"
} > "$OUT"

echo "S3 OK: $(( $(wc -l < "$OUT") - 1 )) aggregate rows -> $OUT"

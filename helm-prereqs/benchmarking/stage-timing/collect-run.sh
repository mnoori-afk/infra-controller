#!/usr/bin/env bash
# collect-run.sh <run-name> <from-iso> <to-iso> [compare-run ...]
#
# The portable data-collection core: pulls one benchmark run's stage-timing
# data from all three sources, cross-validates, and renders CSVs + charts.
# Requires nothing about how the cluster was installed — only a kubectl
# context that reaches it (see lib-env.sh for endpoint overrides).
#
#   S1 sql-stage-timeline.sh    Postgres machine_state_history (ground truth)
#   S2 loki-stage-timeline.py   state_transition_committed log events
#   S3 prom-stage-aggregates.sh Prometheus histograms/counters
#   S4 report.py                merged REPORT.md incl. cross-check verdict
#      combine-stage-stats.py   THE combined CSV (stage-stats.csv, flags column)
#      plot-stage-stats.py      gantt / totals / ranges PNGs (+ comparison)
#
# Artifacts land in $BENCH_RUNS_DIR/<run-name>/ (default ~/stage-timing-runs).
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS/lib-env.sh"

NAME="${1:?usage: collect-run.sh <run-name> <from-iso> <to-iso> [compare-run ...]}"
FROM="${2:?from-iso (e.g. 2026-07-29T12:00:00Z)}"
TO="${3:?to-iso}"
shift 3
COMPARE=("$@")

fail=0
"$SCRIPTS/sql-stage-timeline.sh" "$NAME" "$FROM" "$TO"            || fail=1
python3 "$SCRIPTS/loki-stage-timeline.py" "$NAME" "$FROM" "$TO"   || fail=1
"$SCRIPTS/prom-stage-aggregates.sh" "$NAME" "$FROM" "$TO"         || fail=1
python3 "$SCRIPTS/report.py" "$NAME"                              || fail=1
python3 "$SCRIPTS/combine-stage-stats.py" "$NAME"                 || fail=1
python3 "$SCRIPTS/plot-stage-stats.py" "${COMPARE[@]}" "$NAME"    || fail=1

echo
echo "== $NAME collected -> $RUNS_DIR/$NAME"
echo "   read stage-stats.csv first: an EMPTY flags column means all three"
echo "   sources independently agree; REPORT.md has the cross-check verdict."
exit "$fail"

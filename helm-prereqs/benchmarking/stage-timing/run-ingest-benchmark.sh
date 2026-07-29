#!/usr/bin/env bash
# run-ingest-benchmark.sh <run-name> [hosts=5] [dpus=2]
#
# One machine-a-tron ingest benchmark against an ALREADY-INSTALLED NICo
# cluster (any topology): full MAT cleanup -> timed ingest -> wait until every
# machine reaches `ready` -> collect-run.sh. Cluster install/teardown is out
# of scope here — bring the cluster, this measures it.
#
# IMPORTANT assumptions (see README.md):
# - cleanup-machine-a-tron.sh restarts nico-api, which zeroes its in-process
#   counters; the Prometheus queries in S3 rely on that (absolute values =
#   per-run counts). If your cleanup does NOT restart nico-api, restart it.
# - machine-a-tron ids are deterministic: the run window (recorded here) MUST
#   be passed to any manual extraction, or prior runs' history bleeds in.
# - MAT in single-IP mode needs `allow_insecure_discovery = true` in the site
#   config or every DPU check-in is rejected and fleets wedge in dpuinit.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS/lib-env.sh"
HP="$(cd "$SCRIPTS/../.." && pwd)"   # helm-prereqs/

NAME="${1:?usage: run-ingest-benchmark.sh <run-name> [hosts] [dpus]}"
HOSTS="${2:-5}"
DPUS="${3:-2}"
RUN="$RUNS_DIR/$NAME"; mkdir -p "$RUN"
stamp() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" | tee -a "$RUN/timing.log"; }

: > "$RUN/timing.log"
stamp "RUN $NAME hosts=$HOSTS dpus=$DPUS"

stamp "cleanup START (restarts nico-api -> per-run counters)"
"$HP/cleanup-machine-a-tron.sh" -y > "$RUN/cleanup.log" 2>&1 || stamp "WARN cleanup nonzero"
stamp "cleanup DONE"

date -u '+%Y-%m-%dT%H:%M:%SZ' > "$RUN/window-start.txt"
stamp "ingest START"
( cd "$HP" && MAT_MODE=scale HOST_COUNT="$HOSTS" DPU_PER_HOST="$DPUS" \
      ./setup-machine-a-tron.sh -y ) > "$RUN/mat.log" 2>&1 \
    || stamp "WARN mat script nonzero (ingestion may continue cluster-side)"

EXPECT=$(( HOSTS * (1 + DPUS) ))
WAIT_MIN=$(( 45 + HOSTS * 3 ))
VERDICT=TIMEOUT
for i in $(seq 1 "$WAIT_MIN"); do
    S=$(psql_q "SELECT count(*) FILTER (WHERE controller_state->>'state'='ready'),
                count(*) FILTER (WHERE controller_state->>'state'='failed') FROM machines" \
        2>/dev/null | head -1)
    R="${S%%,*}"; F="${S##*,}"
    [[ "${R:-0}" == "$EXPECT" ]] && { VERDICT=ALL-READY; break; }
    [[ "${F:-0}" != "0" && -n "$F" ]] && { VERDICT="FAILED($F)"; break; }
    sleep 60
done
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$RUN/window-end.txt"
stamp "ingest DONE verdict=$VERDICT after ${i}min"

TO=$(date -u -d '+2 minutes' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -v+2M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u '+%Y-%m-%dT%H:%M:%SZ')
"$SCRIPTS/collect-run.sh" "$NAME" "$(cat "$RUN/window-start.txt")" "$TO" | tee -a "$RUN/timing.log"
stamp "RUN $NAME COMPLETE verdict=$VERDICT"
[[ "$VERDICT" == "ALL-READY" ]]

#!/usr/bin/env bash
# S1 — per-machine stage timeline from machine_state_history (ground truth).
# Usage: sql-stage-timeline.sh <run-name> [from-iso] [to-iso]
# Writes runs/<run-name>/timeline-sql.csv:
#   machine_id,seq,state,substate,entered_at,exited_at,dwell_s
# Host machines only (DPU rows mirror the host state). The last row per
# machine has empty exited_at/dwell_s (still in that state at extraction).
#
# ALWAYS pass the run window: machine-a-tron machine ids are deterministic,
# so a re-created fleet REUSES the previous fleet's ids and inherits its
# machine_state_history rows (cleanup does not truncate history; the 250-row
# trigger caps but keeps them). Unfiltered output mixes runs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib-env.sh"

NAME="${1:?usage: sql-stage-timeline.sh <run-name> [from-iso] [to-iso]}"
FROM="${2:-1970-01-01T00:00:00Z}"
TO="${3:-2100-01-01T00:00:00Z}"
OUT="$RUNS_DIR/$NAME/timeline-sql.csv"
mkdir -p "$RUNS_DIR/$NAME"

# Substate extraction per ManagedHostState serde shape (observed in the DB):
#   hostinit            {"machine_state": {"state": "..."}}
#   dpudiscoveringstate {"dpu_states": {"states": {<dpu>: {"dpudiscoverystate": "..."}}}}
#   dpuinit             {"dpu_states": {"states": {<dpu>: {"dpustate": "..."}}}}
#   validation/cleanup  nested or plain-string variants — coalesce both.
# Per-DPU maps aggregate to the sorted distinct substates joined with '+'.
read -r -d '' SQL <<SQLEOF || true
COPY (
WITH hist AS (
    SELECT h.object_id,
           row_number() OVER w                    AS seq,
           h.state,
           h.timestamp                            AS entered_at,
           lead(h.timestamp) OVER w               AS exited_at
    FROM machine_state_history h
    WHERE h.object_id IN (SELECT id FROM machines WHERE $HOST_MACHINES_FILTER)
      AND h.timestamp >= '$FROM'::timestamptz
      AND h.timestamp <= '$TO'::timestamptz
    WINDOW w AS (PARTITION BY h.object_id ORDER BY h.timestamp, h.id)
)
SELECT object_id                                  AS machine_id,
       seq,
       state->>'state'                            AS state,
       COALESCE(
           state->'machine_state'->>'state',
           (SELECT string_agg(DISTINCT COALESCE(v->>'dpudiscoverystate', v->>'dpustate', v->>'state', v#>>'{}'), '+')
              FROM jsonb_each(state->'dpu_states'->'states') AS e(k, v)),
           state->'validation_state'->>'state',
           state->>'validation_state',
           state->'cleanup_state'->>'state',
           state->>'cleanup_state',
           state->'reprovision_state'->>'state',
           state->>'reprovision_state',
           ''
       )                                          AS substate,
       to_char(entered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS entered_at,
       to_char(exited_at  AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS exited_at,
       round(EXTRACT(EPOCH FROM (exited_at - entered_at))::numeric, 3) AS dwell_s
FROM hist
ORDER BY machine_id, seq
) TO STDOUT WITH CSV HEADER
SQLEOF

# The COPY can be large (45k rows at 1000 hosts) and the master can be under
# write pressure or mid-failover at extraction time — retry, re-resolving the
# master each attempt, and reject partial extracts (fewer rows than machines).
EXPECT_MACHINES=$(psql_q "SELECT count(*) FROM machines WHERE $HOST_MACHINES_FILTER" 2>/dev/null | head -1)
for _attempt in 1 2 3; do
    POD="$(pg_pod)"
    [[ -n "$POD" ]] || { echo "WARN: no postgres master pod (attempt $_attempt)" >&2; sleep 20; continue; }
    if bounded 300 kubectl exec -n "$PG_NS" "$POD" -c postgres -- \
        psql -U postgres -d "$PG_DB" -c "$SQL" > "$OUT"; then
        _GOT=$(tail -n +2 "$OUT" | cut -d, -f1 | sort -u | wc -l | tr -d " ")
        if [[ -z "$EXPECT_MACHINES" || "$_GOT" -ge "${EXPECT_MACHINES:-0}" ]]; then
            break
        fi
        echo "WARN: partial extract ($_GOT/${EXPECT_MACHINES} machines) on attempt $_attempt — retrying" >&2
    else
        echo "WARN: COPY failed on attempt $_attempt — retrying" >&2
    fi
    [[ "$_attempt" == 3 ]] && { echo "ERROR: SQL extraction incomplete after 3 attempts" >&2; exit 1; }
    sleep 30
done

ROWS=$(( $(wc -l < "$OUT") - 1 ))
MACHINES=$(tail -n +2 "$OUT" | cut -d, -f1 | sort -u | wc -l)
CAPPED=$(tail -n +2 "$OUT" | cut -d, -f2 | sort -n | tail -1)
echo "S1 OK: $ROWS transitions across $MACHINES host machines -> $OUT"
[[ "${CAPPED:-0}" -ge 250 ]] && echo "WARN: some machine hit the 250-row history retention cap — its early transitions are gone" >&2
exit 0

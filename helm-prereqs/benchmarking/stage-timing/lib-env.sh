#!/usr/bin/env bash
# lib-env.sh — shared environment for the stage-timing benchmarking toolkit.
# Source, don't execute. Everything talking to the cluster is time-bounded.
#
# Cluster-agnostic: works against any NICo install (single-node dev or a real
# multi-node cluster) reachable through the current kubectl context. Override
# points, all env vars:
#   BENCH_RUNS_DIR  where run artifacts are written (default ~/stage-timing-runs)
#   PROM_URL        e.g. http://<ip>:9090 — skip service discovery entirely
#   LOKI_URL        e.g. http://<ip>:3100 — skip service discovery entirely
#   PG_NS / PG_DB   postgres namespace (default postgres) / db (nico_system_nico)
#
# NOTE ON ENDPOINT REACHABILITY: the *_url discovery below returns ClusterIP
# URLs, which are only reachable from a cluster node (or inside a pod). When
# running the toolkit from a workstation, port-forward instead and set:
#   kubectl -n <ns> port-forward svc/<prometheus-svc> 9090:9090 &  PROM_URL=http://127.0.0.1:9090
#   kubectl -n <ns> port-forward svc/<loki-svc>       3100:3100 &  LOKI_URL=http://127.0.0.1:3100

RUNS_DIR="${BENCH_RUNS_DIR:-$HOME/stage-timing-runs}"
mkdir -p "$RUNS_DIR"

# GNU timeout is absent on stock macOS (present on Linux / brew coreutils as
# gtimeout); fall back to unbounded rather than dying on command-not-found.
if command -v timeout >/dev/null 2>&1; then _TMO="timeout"
elif command -v gtimeout >/dev/null 2>&1; then _TMO="gtimeout"
else _TMO=""
fi
bounded() { local _secs="$1"; shift; ${_TMO:+"$_TMO" "$_secs"} "$@"; }
KUBECTL="bounded 30 kubectl"

# ISO-8601 Z -> epoch seconds, portably (BSD date has no -d; python3 is
# already a hard dependency of the analyzers).
iso_epoch() {
    python3 -c 'import sys; from datetime import datetime, timezone
print(int(datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()))' "$1"
}
PG_NS="${PG_NS:-postgres}"
PG_DB="${PG_DB:-nico_system_nico}"

pg_pod() {
    $KUBECTL get pods -n "$PG_NS" -l spilo-role=master -o name 2>/dev/null \
        | head -1 | cut -d/ -f2
}

# psql <query> — one-shot, tuples-only, comma-separated, time-bounded
psql_q() {
    local pod; pod="$(pg_pod)"
    [[ -n "$pod" ]] || { echo "ERROR: no postgres master pod in ns $PG_NS" >&2; return 1; }
    bounded 60 kubectl exec -n "$PG_NS" "$pod" -c postgres -- \
        psql -U postgres -d "$PG_DB" -tA -F',' -c "$1"
}

# Find a service by trying (namespace, name) pairs; echo http://IP:PORT
_svc_url() {
    local port="$1"; shift
    local ns name ip
    for pair in "$@"; do
        ns="${pair%%/*}"; name="${pair##*/}"
        ip=$($KUBECTL get svc -n "$ns" "$name" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
        [[ -n "$ip" && "$ip" != "None" ]] && { echo "http://$ip:$port"; return 0; }
    done
    return 1
}

# helm-prereqs/observability stack (release `obs`, fullnameOverride obs):
# Prometheus = obs-prometheus.monitoring:9090, Loki = loki.loki:3100.
prom_url() {
    [[ -n "${PROM_URL:-}" ]] && { echo "$PROM_URL"; return; }
    _svc_url 9090 \
        "monitoring/obs-prometheus" \
        "monitoring/prometheus-operated"
}

loki_url() {
    [[ -n "${LOKI_URL:-}" ]] && { echo "$LOKI_URL"; return; }
    _svc_url 3100 \
        "loki/loki" \
        "monitoring/loki"
}

# Host machines only: DPU rows mirror the host's state and would triple-count.
HOST_MACHINES_FILTER="id NOT IN (SELECT DISTINCT attached_dpu_machine_id
    FROM machine_interfaces WHERE attached_dpu_machine_id IS NOT NULL)"

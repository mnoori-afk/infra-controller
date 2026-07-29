#!/usr/bin/env bash
# run-full-benchmark-k8s.sh <run-name> [hosts=5] [dpus=2]
#
# Full reinstall-per-run stage-timing benchmark for a REAL Kubernetes cluster
# (kubeadm/kubespray/multi-node — anything the helm-prereqs installer targets):
#
#   clean.sh  ->  setup.sh --with-observability (Core at the instrumented
#   image, Loki + Prometheus + OTEL + Tempo, NICo ServiceMonitors)  ->
#   run-ingest-benchmark.sh (machine-a-tron ingest + 3-channel collection)
#
# A fresh install per run is the only reset that restores baseline ingestion
# behaviour on recycled clusters, so that is the default. Set SKIP_INSTALL=true
# to reuse the cluster as-is (quick iteration: cleanup + ingest + collect only).
#
# Environment — required:
#   BENCH_KUBE_CONTEXT    Safety latch: must equal `kubectl config
#                         current-context`. clean.sh destroys the whole NICo
#                         footprint; this proves the destruction is aimed at
#                         the cluster you think it is.
#   NICO_IMAGE_REGISTRY   e.g. <registry>/<org>/carbide-dev
#   NICO_CORE_IMAGE_TAG   Core tag — must be an instrumented build (this
#                         branch's crates) or the Loki/Prometheus channels
#                         collect nothing (SQL still works).
#   MAT_IMAGE_TAG         machine-a-tron image tag.
#   CORE_VALUES           Site Core values file. Its nicoApiSiteConfig MUST set
#                         allow_insecure_discovery = true (machine-a-tron
#                         single-IP mode) or fleets wedge in dpuinit.
# Environment — optional:
#   REGISTRY_PULL_SECRET  Registry key; required on a freshly cleaned cluster
#                         (setup.sh and machine-a-tron both create pull
#                         secrets from it).
#   METALLB_CONFIG        Site MetalLB manifest/kustomize dir for setup.sh.
#   SITE_OVERLAY          Site kustomize overlay for setup.sh.
#   GRAFANA_VIP           MetalLB VIP for Grafana (else ClusterIP).
#   WITH_REST=false       true = full setup.sh including the REST stack. The
#                         benchmark never talks to REST, so default is the
#                         lean --skip-rest --skip-flow install.
#   SKIP_INSTALL=false    true = skip clean.sh + setup.sh entirely.
#   PROM_URL / LOKI_URL   Endpoint overrides. Unset = this script manages
#                         self-healing local port-forwards for the collection
#                         phase (needed whenever it runs off-cluster).
#   BENCH_RUNS_DIR        Artifact dir (default ~/stage-timing-runs).
#
# Exit code: 0 iff the ingest reached ALL-READY and collection succeeded.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HP="$(cd "$SCRIPTS/../.." && pwd)"   # helm-prereqs/

NAME="${1:?usage: run-full-benchmark-k8s.sh <run-name> [hosts] [dpus]}"
HOSTS="${2:-5}"
DPUS="${3:-2}"
WITH_REST="${WITH_REST:-false}"
SKIP_INSTALL="${SKIP_INSTALL:-false}"

fail() { echo "ERROR: $*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------
CTX="$(kubectl config current-context 2>/dev/null)" || fail "kubectl has no current context"
[[ -n "${BENCH_KUBE_CONTEXT:-}" ]] || fail "BENCH_KUBE_CONTEXT is unset — set it to '$CTX' to confirm the target cluster"
[[ "$BENCH_KUBE_CONTEXT" == "$CTX" ]] || fail "BENCH_KUBE_CONTEXT='$BENCH_KUBE_CONTEXT' but current context is '$CTX' — refusing to touch it"
[[ -n "${NICO_IMAGE_REGISTRY:-}" ]] || fail "NICO_IMAGE_REGISTRY is unset"
[[ -n "${MAT_IMAGE_TAG:-}" ]]      || fail "MAT_IMAGE_TAG is unset"
if [[ "$SKIP_INSTALL" != "true" ]]; then
    [[ -n "${NICO_CORE_IMAGE_TAG:-}" ]] || fail "NICO_CORE_IMAGE_TAG is unset"
    [[ -n "${CORE_VALUES:-}" && -f "${CORE_VALUES:-}" ]] || fail "CORE_VALUES is unset or not a file"
    grep -q "allow_insecure_discovery[[:space:]]*=[[:space:]]*true" "$CORE_VALUES" \
        || echo "WARNING: CORE_VALUES does not set allow_insecure_discovery=true — machine-a-tron fleets will wedge in dpuinit" >&2
fi

RUNS_DIR="${BENCH_RUNS_DIR:-$HOME/stage-timing-runs}"
RUN="$RUNS_DIR/$NAME"; mkdir -p "$RUN"
stamp() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" | tee -a "$RUN/full-benchmark.log"; }
: > "$RUN/full-benchmark.log"
stamp "FULL RUN $NAME context=$CTX hosts=$HOSTS dpus=$DPUS with_rest=$WITH_REST skip_install=$SKIP_INSTALL"

# --- Phase 1: fresh install ------------------------------------------------
if [[ "$SKIP_INSTALL" != "true" ]]; then
    stamp "clean.sh START (full teardown)"
    ( cd "$HP" && ./clean.sh ) > "$RUN/clean.log" 2>&1 || stamp "WARN clean.sh nonzero (continuing — setup is idempotent)"
    stamp "clean.sh DONE"

    SETUP_ARGS=(-y --with-observability --core-values "$CORE_VALUES")
    [[ "$WITH_REST" == "true" ]] || SETUP_ARGS+=(--skip-rest --skip-flow)
    [[ -n "${METALLB_CONFIG:-}" ]] && SETUP_ARGS+=(--metallb-config "$METALLB_CONFIG")
    [[ -n "${SITE_OVERLAY:-}" ]]   && SETUP_ARGS+=(--site-overlay "$SITE_OVERLAY")
    stamp "setup.sh START (${SETUP_ARGS[*]})"
    ( cd "$HP" && ./setup.sh "${SETUP_ARGS[@]}" ) > "$RUN/setup.log" 2>&1 \
        || fail "setup.sh failed — see $RUN/setup.log"
    stamp "setup.sh DONE"

    kubectl rollout status deploy/nico-api -n nico-system --timeout=300s >/dev/null \
        || fail "nico-api never became ready after install"
    SM=$(kubectl get servicemonitor -n nico-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "${SM:-0}" -ge 1 ]] || fail "no NICo ServiceMonitors after install — Prometheus channel would be empty"
    stamp "install sanity OK (nico-api ready, ${SM} servicemonitors)"
fi

# --- Phase 2: collection endpoints -----------------------------------------
# Off-cluster runs cannot reach the ClusterIPs lib-env.sh discovers; keep two
# self-healing port-forwards alive for the whole run so the collection phase
# always has endpoints. Ports are derived from PID to allow concurrent runs.
PF_PIDS=()
if [[ -z "${PROM_URL:-}" ]]; then
    PROM_PORT=$(( 20000 + $$ % 10000 ))
    ( while true; do kubectl -n monitoring port-forward svc/obs-prometheus "$PROM_PORT":9090 >/dev/null 2>&1; sleep 2; done ) &
    PF_PIDS+=($!); export PROM_URL="http://127.0.0.1:$PROM_PORT"
    stamp "port-forward obs-prometheus -> $PROM_URL"
fi
if [[ -z "${LOKI_URL:-}" ]]; then
    LOKI_PORT=$(( 31000 + $$ % 10000 ))
    ( while true; do kubectl -n loki port-forward svc/loki "$LOKI_PORT":3100 >/dev/null 2>&1; sleep 2; done ) &
    PF_PIDS+=($!); export LOKI_URL="http://127.0.0.1:$LOKI_PORT"
    stamp "port-forward loki -> $LOKI_URL"
fi
cleanup_pf() {
    for pid in ${PF_PIDS[@]+"${PF_PIDS[@]}"}; do
        pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
    done
    # Reap so the interactive shell doesn't print "Terminated" after exit.
    wait ${PF_PIDS[@]+"${PF_PIDS[@]}"} 2>/dev/null
}
trap cleanup_pf EXIT

# --- Phase 3: ingest + collect ---------------------------------------------
stamp "delegating to run-ingest-benchmark.sh"
"$SCRIPTS/run-ingest-benchmark.sh" "$NAME" "$HOSTS" "$DPUS"
RC=$?
stamp "FULL RUN $NAME COMPLETE rc=$RC — artifacts: $RUN"
exit "$RC"

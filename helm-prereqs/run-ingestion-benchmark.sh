#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# =============================================================================
# run-ingestion-benchmark.sh — one reproducible knob-tuning run (#3738)
#
# Drives a full machine-a-tron scale run and archives every artifact the
# tuning campaign needs to compare runs:
#
#   1. cleanup-machine-a-tron.sh -y                  (identical starting state)
#   2. MAT_MODE=scale setup-machine-a-tron.sh -y     (with this run's SCALE_* knobs;
#      its Phase-10 CSV lands in the results dir)
#   3. ingestion-rate-report.sh                      (exact curves from DB clocks)
#   4. optional Prometheus range pulls of the headline series for the run window
#
# Record the run afterwards in docs/development/machine-a-tron-ingestion-tuning-results.md.
#
# Usage (one knob per run — see the E1–E7 matrix in the tuning plan):
#   RUN_LABEL=B0 HOST_COUNT=1000 ./run-ingestion-benchmark.sh
#   RUN_LABEL=E1 HOST_COUNT=1000 SCALE_RUN_INTERVAL=30s ./run-ingestion-benchmark.sh
#
# Environment:
#   RUN_LABEL       REQUIRED — matrix id (B0, E1, ...); names the results dir.
#   HOST_COUNT      default 1000;  DPU_PER_HOST default 2.
#   SCALE_*         knob overrides, passed through to setup-machine-a-tron.sh
#                   (SCALE_RUN_INTERVAL, SCALE_CONCURRENT_EXPLORATIONS,
#                    SCALE_EXPLORATIONS_PER_RUN, SCALE_MACHINES_CREATED_PER_RUN,
#                    SCALE_FW_CONCURRENCY, SCALE_FW_RUN_INTERVAL,
#                    SCALE_STATE_MAX_CONCURRENCY)
#   RESULTS_ROOT    default ~/mat-bench-results; run dir = <root>/<RUN_LABEL>-<utc stamp>
#   PROM_SNAPSHOT   default true; set false to skip the Prometheus pulls.
#   PROM_SVC        default obs-kube-prometheus-st-prometheus:9090 (kps release "obs",
#                   ns monitoring) — the launchpad/nvcert observability stack.
#   KUBECONFIG      the target site, as for setup-machine-a-tron.sh.
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

RUN_LABEL="${RUN_LABEL:?RUN_LABEL is required (e.g. RUN_LABEL=B0)}"
HOST_COUNT="${HOST_COUNT:-1000}"
DPU_PER_HOST="${DPU_PER_HOST:-2}"
RESULTS_ROOT="${RESULTS_ROOT:-$HOME/mat-bench-results}"
PROM_SNAPSHOT="${PROM_SNAPSHOT:-true}"
PROM_SVC="${PROM_SVC:-obs-kube-prometheus-st-prometheus:9090}"

STAMP="$(date -u +%Y%m%d-%H%M%S)"
RESULTS_DIR="${RESULTS_ROOT}/${RUN_LABEL}-${STAMP}"
mkdir -p "${RESULTS_DIR}"

# Self-describing run manifest: the knobs as requested (the CSV additionally
# embeds the EFFECTIVE values the site config ended up with).
{
    echo "run_label=${RUN_LABEL}"
    echo "host_count=${HOST_COUNT} dpu_per_host=${DPU_PER_HOST}"
    echo "started_utc=$(date -u +%FT%TZ)"
    env | grep -E '^SCALE_' | sort || true
} > "${RESULTS_DIR}/run-manifest.txt"
echo "==> run ${RUN_LABEL}: results in ${RESULTS_DIR}"
cat "${RESULTS_DIR}/run-manifest.txt"

echo "==> [1/4] cleanup (identical starting state)"
"${DIR}/cleanup-machine-a-tron.sh" -y 2>&1 | tee "${RESULTS_DIR}/cleanup.log" >/dev/null
echo "    cleanup done"

echo "==> [2/4] scale run (${HOST_COUNT}x${DPU_PER_HOST})"
T_START="$(date -u +%s)"
INGEST_RATE_CSV="${RESULTS_DIR}/ingestion-rates.csv" \
MAT_MODE=scale HOST_COUNT="${HOST_COUNT}" DPU_PER_HOST="${DPU_PER_HOST}" \
    "${DIR}/setup-machine-a-tron.sh" -y 2>&1 | tee "${RESULTS_DIR}/setup.log"
T_END="$(date -u +%s)"
echo "wall_clock_seconds=$((T_END - T_START))" >> "${RESULTS_DIR}/run-manifest.txt"
echo "    wall clock: $((T_END - T_START))s"

echo "==> [3/4] exact ingestion curves from the DB's own timestamps"
"${DIR}/ingestion-rate-report.sh" --csv > "${RESULTS_DIR}/rate-report.txt" 2>&1 || \
    echo "    WARNING: ingestion-rate-report.sh failed (see rate-report.txt)"

if [[ "${PROM_SNAPSHOT}" == "true" ]]; then
    echo "==> [4/4] Prometheus range pulls for the run window"
    # 60s steps over [start-5m, end+5m]; one JSON file per headline series.
    # Served through the API-server service proxy — no port-forward needed.
    _P_START=$((T_START - 300)); _P_END=$((T_END + 300))
    prom_pull() {   # $1 = output name, $2 = promQL
        local out="${RESULTS_DIR}/prom/$1.json" q
        q="$(printf '%s' "$2" | jq -sRr @uri)"
        mkdir -p "${RESULTS_DIR}/prom"
        if ! kubectl get --raw "/api/v1/namespaces/monitoring/services/${PROM_SVC}/proxy/api/v1/query_range?query=${q}&start=${_P_START}&end=${_P_END}&step=60" \
            > "${out}" 2>/dev/null; then
            echo "    WARNING: prom pull '$1' failed (observability stack not installed?)"
            rm -f "${out}"
        fi
    }
    prom_pull ready-rate            'sum(rate(carbide_machines_state_entered_total{state="ready"}[10m])) * 3600'
    prom_pull machines-per-state    'sum by (state) (carbide_machines_per_state)'
    prom_pull above-sla             'sum by (state, substate) (carbide_machines_per_state_above_sla)'
    prom_pull preingestion-states   'sum by (state) (carbide_preingestion_per_state)'
    prom_pull preingestion-edges    'sum by (from, to) (rate(carbide_preingestion_state_transitions_total[10m]))'
    prom_pull se-cycle-p90          'histogram_quantile(0.9, sum by (le) (rate(carbide_site_explorer_iteration_latency_milliseconds_bucket[15m])))'
    prom_pull se-phase-time         'sum by (phase) (rate(carbide_site_explorer_phase_latency_milliseconds_sum[15m]))'
    prom_pull e2e-duration-p90      'histogram_quantile(0.9, sum by (le, anchor) (rate(carbide_machine_ingestion_duration_seconds_bucket[30m])))'
    prom_pull redfish-red           'sum by (backend, outcome) (rate(carbide_external_call_duration_milliseconds_count[5m]))'
    prom_pull knobs                 'carbide_config_knob_value'
    prom_pull infra-cpu             'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=~"nico-system|postgres", container!=""}[5m]))'
else
    echo "==> [4/4] Prometheus pulls SKIPPED (PROM_SNAPSHOT=false)"
fi

echo ""
echo "==> run ${RUN_LABEL} complete — artifacts:"
ls -l "${RESULTS_DIR}" "${RESULTS_DIR}/prom" 2>/dev/null || true
echo ""
echo "Record the run in docs/development/machine-a-tron-ingestion-tuning-results.md"

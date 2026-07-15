#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# deploy-observability.sh — stand up a LOCAL observability stack on the launchpad site:
#   Loki (log store) + OTEL collectors (agent DaemonSet + gateway Deployment) + kube-prometheus-stack
#   (Prometheus + Grafana). Mirrors how `forged` does it, but ships logs to LOCAL Loki (NO Panoptes).
#
# Collects:
#   - all k8s pod stdout (nico-*, nico-rest, flow, temporal, rack-manager, ...) via the agent DaemonSet
#   - ssh-console transcripts via the nico-ssh-console-rs sidecar (enable it in nico-core.launchpad.yaml)
#   - DPU (BlueField) DOCA/HBN/kernel/auth logs + host metrics via the gateway OTLP/mTLS receiver
#
# Phased so you can stop after any phase. Mirrors the style of nico/deploy-flow.sh.
#
# Grafana has NO auth (anonymous Admin, login form disabled — see values-kube-prometheus-stack.yaml);
# Loki (auth_enabled:false) and the collectors are also auth-free. Internal-only site (VIP/tunnel).
#
# Usage:
#   ./deploy-observability.sh                 # phases 1-4 (Loki, agent, prometheus/grafana) — no certs
#   WITH_DPU=true ./deploy-observability.sh   # + phase 5: DPU OTLP/mTLS gateway (see the mTLS check below)
#
# Env overrides: CA_SRC_NS (default nico-rest), LOKI_CHART_VER, OTEL_CHART_VER, KPS_CHART_VER
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CA_SRC_NS="${CA_SRC_NS:-nico-rest}"
LOKI_CHART_VER="${LOKI_CHART_VER:-5.15.0}"
KPS_CHART_VER="${KPS_CHART_VER:-59.1.0}"
OTEL_CHART_VER="${OTEL_CHART_VER:-0.106.0}"   # opentelemetry-collector chart; ships a <=0.106 image (has loki exporter)

need() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found" >&2; exit 1; }; }
need kubectl; need helm

echo "==> [1/9] helm repos"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

echo "==> [2/9] namespaces (loki, otel, monitoring)"
for ns in loki otel monitoring; do kubectl create ns "$ns" 2>/dev/null || true; done

echo "==> [3/9] Loki (single-binary, local-path 50Gi)"
helm upgrade --install loki grafana/loki --version "$LOKI_CHART_VER" -n loki \
  -f "$DIR/values-loki.yaml" --wait --timeout 300s

echo "==> [4/9] OTEL collector AGENT (DaemonSet: all pod logs -> Loki)"
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector --version "$OTEL_CHART_VER" -n otel \
  -f "$DIR/values-otel-collector-agent.yaml" --wait --timeout 300s

echo "==> [5/9] ensure prometheus-operator CRDs (chart runs with crds.enabled=false; the cluster may already"
echo "          have a PARTIAL set owned by helmfile/another manager — so apply only the MISSING ones,"
echo "          server-side, which never touches/downgrades existing CRDs)"
CRD_TMP="$(mktemp -d)"
helm pull prometheus-community/kube-prometheus-stack --version "$KPS_CHART_VER" --untar -d "$CRD_TMP" >/dev/null
CRD_DIR="$CRD_TMP/kube-prometheus-stack/charts/crds/crds"
for crd in prometheuses alertmanagers prometheusrules servicemonitors podmonitors thanosrulers probes scrapeconfigs; do
  if kubectl get crd "${crd}.monitoring.coreos.com" >/dev/null 2>&1; then
    echo "    exists : ${crd}"
  else
    echo "    install: ${crd} (missing)"
    kubectl apply --server-side -f "$CRD_DIR/crd-${crd}.yaml"
  fi
done
rm -rf "$CRD_TMP"

echo "==> [6/9] kube-prometheus-stack (Prometheus + Grafana [anonymous Admin, no login] at grafana.forge 172.16.2.31)"
helm upgrade --install obs prometheus-community/kube-prometheus-stack \
  --version "$KPS_CHART_VER" -n monitoring -f "$DIR/values-kube-prometheus-stack.yaml" --wait --timeout 600s

if [ "${WITH_DPU:-false}" = "true" ]; then
  echo "==> [7/9] DPU mTLS pre-flight. VERIFIED live on DPU 172.16.2.76 (2026-07-15): the DPU's"
  echo "    /etc/otelcol-contrib/certs/ca.pem = CN=site-root (SHA256 31:9A:1F:...:F8:3E) and its client cert"
  echo "    is ALSO signed by site-root. So the gateway cert must come from site-issuer (leaf signed by"
  echo "    site-root); the cert secret's own ca.crt (= site-root) is reused as the client_ca — no CA copy."
  kubectl get clusterissuer site-issuer -o jsonpath='{.spec.ca.secretName}{"\n"}' 2>/dev/null | grep -qx site-root \
    || { echo "ERROR: site-issuer is not a ca-issuer backed by 'site-root' — check the site CA" >&2; exit 1; }

  echo "==> [8/9] issue the gateway server cert from site-issuer"
  kubectl apply -f "$DIR/otel-receiver-certificate.yaml"
  # (If you're re-pointing the issuer of an EXISTING cert and cert-manager doesn't reissue, force it:
  #   kubectl -n otel delete secret otel-receiver-tls --ignore-not-found )
  kubectl wait --for=condition=Ready certificate/otel-receiver-tls -n otel --timeout=120s

  echo "==> [9/9] OTEL collector GATEWAY (Deployment: OTLP/mTLS on 172.16.2.30:443 -> Loki + Prometheus)"
  helm upgrade --install otel-collector-gateway open-telemetry/opentelemetry-collector --version "$OTEL_CHART_VER" -n otel \
    -f "$DIR/values-otel-collector-gateway.yaml" --wait --timeout 300s
else
  echo "==> [7/9] DPU gateway SKIPPED (set WITH_DPU=true — the DPU otelcol trusts site-root; our cert uses site-issuer)"
fi

echo
echo "==> pods / services"
kubectl -n loki get pods
kubectl -n otel get pods,svc
kubectl -n monitoring get pods | head
echo
echo "DONE."
echo "  Loki:          loki.loki.svc.cluster.local:3100"
echo "  Grafana:       grafana.forge -> 172.16.2.31   (add unbound A record + MetalLB range .30-.39)"
[ "${WITH_DPU:-false}" = "true" ] && echo "  OTLP receiver: otel-receiver.forge -> 172.16.2.30:443 (mTLS)"
echo
echo "Next: (a) add the .30/.31 VIPs to metallb-config + unbound localData and helm-upgrade nico-core;"
echo "      (b) enable the ssh-console sidecar: nico-ssh-console-rs.lokiLogCollector.enabled=true + Core upgrade + rollout restart."

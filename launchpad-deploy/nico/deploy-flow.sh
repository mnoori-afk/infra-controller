#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# deploy-flow.sh — install + configure NICo Flow (nico-flow/psm/nsm) on the launchpad site.
#
# Mirrors helm-prereqs/setup.sh Phase 7h, plus the two prereqs that install-rest-1.6.0.sh skipped:
#   - the Temporal `flow` namespace (flow workers panic on startup without it)
#   - an image-pull-secret in the `flow` namespace (copied from nico-rest)
#
# The DB creds (flow/psm/nsm.nico.nico-pg-cluster.credentials) + vault tokens are already synced by the
# nico-prereqs ESO/hooks (flow.enabled=true), so this script does NOT create them — it fail-fasts if
# any is missing. NO SECRETS in this file (image-pull-secret is copied from the live nico-rest ns).
#
# Usage:
#   ./deploy-flow.sh                 # deploy Flow
#   ENABLE_AGENT_FLOW=true ./deploy-flow.sh   # + flip site-agent FLOW_GRPC_ENABLED=true and restart it
#
# Env overrides: REG, TAG, NS, PULL_SECRET_SRC_NS

set -euo pipefail

REG="${REG:-nvcr.io/0837451325059433/carbide-dev}"
TAG="${TAG:-v2.1.0-pr-14-g0d5452b9a}"      # Flow ships on the REST image line; matches the running REST/site-agent
NS="${NS:-flow}"
PULL_SECRET_SRC_NS="${PULL_SECRET_SRC_NS:-nico-rest}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
CHART="${CHART:-$REPO/helm/charts/nico-flow}"
TEMPORAL_NS="${TEMPORAL_NS:-temporal}"

need() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found" >&2; exit 1; }; }
need kubectl; need helm; need jq
[ -f "$CHART/Chart.yaml" ] || { echo "ERROR: flow chart not found at $CHART" >&2; exit 1; }

TLS_ARGS="--tls-cert-path /var/secrets/temporal/certs/server-interservice/tls.crt \
--tls-key-path /var/secrets/temporal/certs/server-interservice/tls.key \
--tls-ca-path /var/secrets/temporal/certs/server-interservice/ca.crt \
--tls-server-name interservice.server.temporal.local"

echo "==> [1/6] Temporal '$NS' namespace"
kubectl -n "$TEMPORAL_NS" exec deploy/temporal-admintools -- sh -c \
  "temporal operator namespace create --namespace $NS --address temporal-frontend.temporal:7233 $TLS_ARGS" 2>&1 \
  | grep -iv "already exists" || true

echo "==> [2/6] read the registry dockerconfigjson from $PULL_SECRET_SRC_NS/image-pull-secret"
# The chart OWNS image-pull-secret (imagePullSecret.create=true, default dockerconfigjson={"auths":{}}),
# so we MUST feed it the real creds via --set — a manual copy gets clobbered by the empty default on
# helm install. Reuse the working creds from the running nico-rest namespace (already base64).
DOCKERCFG=$(kubectl -n "$PULL_SECRET_SRC_NS" get secret image-pull-secret -o jsonpath='{.data.\.dockerconfigjson}')
[ -n "$DOCKERCFG" ] || { echo "ERROR: no dockerconfigjson in $PULL_SECRET_SRC_NS/image-pull-secret" >&2; exit 1; }
echo "$DOCKERCFG" | base64 -d | jq -e '.auths | keys | length > 0' >/dev/null 2>&1 \
  && echo "    source creds present" || { echo "ERROR: source image-pull-secret has empty auths" >&2; exit 1; }

echo "==> [3/6] verify DB creds + vault tokens are synced (fail-fast)"
for s in flow.nico.nico-pg-cluster.credentials psm.nico.nico-pg-cluster.credentials \
         nsm.nico.nico-pg-cluster.credentials psm-vault-token nsm-vault-token; do
  kubectl -n "$NS" get secret "$s" >/dev/null 2>&1 || {
    echo "ERROR: missing secret '$s' in $NS — check nico-prereqs flow.enabled + ESO/vault hooks" >&2; exit 1; }
  echo "    ok: $s"
done

# --set with bracket index is quoted so zsh/bash never glob-expands it.
FLOW_ARGS=( --namespace "$NS" --create-namespace
  --set "global.image.repository=$REG"
  --set "global.image.tag=$TAG"
  --set 'global.imagePullSecrets[0].name=image-pull-secret'
  --set imagePullSecret.create=true
  --set-string "imagePullSecret.dockerconfigjson=$DOCKERCFG" )

echo "==> [4/6] pre-apply Certificates + Helm ownership (ns pre-exists from the vault hook)"
helm template flow "$CHART" "${FLOW_ARGS[@]}" --show-only templates/certificate.yaml | kubectl apply -f -
for c in flow-certificate temporal-client-certs; do
  kubectl annotate certificate/"$c" -n "$NS" \
    meta.helm.sh/release-name=flow meta.helm.sh/release-namespace="$NS" --overwrite
  kubectl label certificate/"$c" -n "$NS" app.kubernetes.io/managed-by=Helm --overwrite
done
kubectl annotate namespace "$NS" \
  meta.helm.sh/release-name=flow meta.helm.sh/release-namespace="$NS" --overwrite
kubectl label namespace "$NS" app.kubernetes.io/managed-by=Helm --overwrite

echo "==> [5/6] wait for certs, then install"
kubectl wait --for=condition=Ready certificate/flow-certificate      -n "$NS" --timeout=120s
kubectl wait --for=condition=Ready certificate/temporal-client-certs -n "$NS" --timeout=120s
helm upgrade --install flow "$CHART" "${FLOW_ARGS[@]}" --timeout 300s --wait

echo "==> [6/6] flow pods:"
kubectl -n "$NS" get pods

if [ "${ENABLE_AGENT_FLOW:-false}" = "true" ]; then
  echo "==> enabling site-agent Flow gRPC (FLOW_GRPC_ENABLED=true) + restart"
  kubectl -n nico-rest get cm nico-rest-site-agent-config -o yaml \
    | sed 's/FLOW_GRPC_ENABLED: .*/FLOW_GRPC_ENABLED: "true"/' | kubectl apply -f -
  kubectl -n nico-rest rollout restart sts/nico-rest-site-agent
  kubectl -n nico-rest rollout status  sts/nico-rest-site-agent --timeout=240s
fi
echo "DONE."

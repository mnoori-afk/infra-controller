#!/usr/bin/env bash
#
# Surgical NICo REST install for the launchpad site (image tag pinned below — currently v2.1.0-pr-14).
#
# WHY THIS EXISTS:
#   helm-prereqs/setup.sh is a *fresh-install* tool — it always re-runs infra
#   phases 1–5 (MetalLB, Vault, external-secrets, nico-prereqs) before reaching
#   the REST phase. On this already-live cluster that (a) failed on a MetalLB CRD
#   server-side-apply ownership conflict and (b) would re-render nico-prereqs with
#   the empty default values (siteName=<empty>), risking the running Core.
#
#   This script replicates ONLY setup.sh Phase 7 (7a–7h), which is fully confined
#   to the nico-rest / postgres / temporal namespaces. It does NOT touch MetalLB,
#   Vault, external-secrets, or the running Core (test11). Flow (7i) is skipped.
#
# USAGE:
#   export REGISTRY_PULL_SECRET='<NGC API key>'   # same one used for Core
#   ./launchpad-bringup/install-rest-1.6.0.sh
#
set -euo pipefail

# ---- fixed inputs for launchpad ---------------------------------------------
# KUBECONFIG: rely on your current context (tsh kube login rg-forge-launchpad) or export KUBECONFIG yourself.
# REPO is auto-derived from this script's location (this script lives at <repo>/launchpad-deploy/),
# so it works on any checkout. Override with REPO=<path> if your layout differs.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${REPO:-$(cd "${_SELF_DIR}/.." && pwd)}"
SCRIPT_DIR="${REPO}/helm-prereqs"
NICO_REST_DIR="${REPO}/rest-api"
NICO_REST_HELM_DIR="${REPO}/helm/rest"
NICO_HELM_CHART="${NICO_REST_HELM_DIR}/nico-rest"
NICO_SITE_AGENT_CHART="${NICO_REST_HELM_DIR}/nico-rest-site-agent"

NICO_IMAGE_REGISTRY="nvcr.io/0837451325059433/carbide-dev"
# Pinned to the currently-deployed launchpad REST/Flow line. The stack was upgraded v1.6.0 -> v2.1.0-pr-14
# on 2026-07-02 (whole set: api/site-manager/site-agent/workflow/cert-manager/flow share this tag). The
# "1.6.0" in this script's filename is legacy — it now installs v2.1.0-pr-14.
NICO_REST_IMAGE_TAG="v2.1.0-pr-14-g0d5452b9a"
# Current launchpad site identity. The site was re-registered via the v2 API on 2026-07-02 (siteId
# 8c894583); the old 7f91b08b bootstrap UUID is orphaned. Re-running this script bootstraps the site-agent
# with this UUID, so it must match the live site. On a FRESH site, register via
# launchpad-deploy/nico/register-rest-site.sh (v2 POST /site mints a new uuid) rather than hardcoding one.
NICO_SITE_UUID="8c894583-bea4-445d-a5bd-46ee0e3cb3fb"
REGISTRY_PULL_USERNAME="${REGISTRY_PULL_USERNAME:-\$oauthtoken}"
# Flow is NOT installed here — it's deployed separately by launchpad-deploy/nico/deploy-flow.sh. The
# site-agent below is installed with FLOW_GRPC_ENABLED=false (correct while Flow is absent). AFTER Flow is
# up, enable agent->Flow via `ENABLE_AGENT_FLOW=true TAG=v2.1.0-pr-14-g0d5452b9a ./deploy-flow.sh`
# (re-running THIS script resets FLOW_GRPC_ENABLED=false, so re-enable afterward).
# RMS is deployed out-of-band in the rack-manager namespace; its config lives in nico-core.launchpad.yaml
# (Core siteConfig: component_manager + [rms] mTLS), NOT here.
SKIP_FLOW="true"

if [[ -z "${REGISTRY_PULL_SECRET:-}" ]]; then
    echo "ERROR: export REGISTRY_PULL_SECRET=<NGC API key> before running." >&2
    exit 1
fi

echo "REST source: ${NICO_REST_DIR}"
echo "REST charts: ${NICO_REST_HELM_DIR}"
echo "Image:       ${NICO_IMAGE_REGISTRY}  tag: ${NICO_REST_IMAGE_TAG}"
echo "Site UUID:   ${NICO_SITE_UUID}"
echo ""

# ---- namespace --------------------------------------------------------------
kubectl create namespace nico-rest 2>/dev/null || true

# ---- 7a. CA signing secret --------------------------------------------------
if kubectl get secret ca-signing-secret -n nico-rest &>/dev/null; then
    echo "=== [7a] ca-signing-secret already present — skipping CA generation ==="
else
    echo "=== [7a] Generating NICo REST CA signing secret ==="
    (cd "${NICO_REST_DIR}" && ./scripts/gen-site-ca.sh)
fi

# ---- 7b. ClusterIssuer ------------------------------------------------------
echo "=== [7b] NICo REST CA issuer ClusterIssuer ==="
(cd "${NICO_REST_DIR}" && kubectl apply -k deploy/kustomize/base/cert-manager-io)

# ---- 7c. NICo REST postgres -------------------------------------------------
echo "=== [7c] NICo REST postgres ==="
(cd "${NICO_REST_DIR}" && kubectl apply -k deploy/kustomize/base/postgres)
kubectl rollout status statefulset/postgres -n postgres --timeout=180s
echo "NICo REST postgres ready"

# ---- 7d. Keycloak (dev IdP; keycloak.enabled=true in nico-rest.yaml) --------
_KC_ENABLED="$(grep -A5 'keycloak:' "${SCRIPT_DIR}/values/nico-rest.yaml" \
    | grep 'enabled:' | head -1 | awk '{print $2}' || echo "false")"
if [[ "${_KC_ENABLED}" == "true" ]]; then
    echo "=== [7d] Keycloak (dev) ==="
    "${SCRIPT_DIR}/keycloak/setup.sh"
    echo "Keycloak ready"
else
    echo "=== [7d] Keycloak — skipped (keycloak.enabled not true) ==="
fi

# ---- 7e. Temporal TLS bootstrap ---------------------------------------------
echo "=== [7e] Temporal TLS bootstrap ==="
(cd "${NICO_REST_DIR}" && kubectl apply -f deploy/kustomize/base/temporal-helm/namespace.yaml)
(cd "${NICO_REST_DIR}" && kubectl apply -f deploy/kustomize/base/temporal-helm/db-creds.yaml)
(cd "${NICO_REST_DIR}" && kubectl apply -f deploy/kustomize/base/temporal-helm/certificates.yaml)
echo "Waiting for temporal TLS certificates..."
kubectl wait --for=condition=Ready certificate/server-interservice-cert -n temporal --timeout=120s
kubectl wait --for=condition=Ready certificate/server-cloud-cert       -n temporal --timeout=120s
kubectl wait --for=condition=Ready certificate/server-site-cert        -n temporal --timeout=120s
echo "Temporal TLS certs ready"

# ---- 7f. Temporal -----------------------------------------------------------
echo "=== [7f] Temporal ==="
helm upgrade --install temporal "${NICO_REST_DIR}/temporal-helm/temporal" \
    --namespace temporal \
    -f "${NICO_REST_DIR}/temporal-helm/temporal/values-kind.yaml" \
    --timeout 300s --wait
echo "Temporal ready"

_TEMPORAL_ADDR="temporal-frontend.temporal:7233"
_TEMPORAL_TLS="--tls-cert-path /var/secrets/temporal/certs/server-interservice/tls.crt \
    --tls-key-path /var/secrets/temporal/certs/server-interservice/tls.key \
    --tls-ca-path /var/secrets/temporal/certs/server-interservice/ca.crt \
    --tls-server-name interservice.server.temporal.local"
echo "Creating Temporal cloud + site namespaces..."
for _ns in cloud site; do
    kubectl exec -n temporal deploy/temporal-admintools -- \
        sh -c "temporal operator namespace create -n ${_ns} --address ${_TEMPORAL_ADDR} ${_TEMPORAL_TLS}" 2>/dev/null || true
done
echo "Temporal namespaces ready"

# ---- 7g. NICo REST umbrella chart -------------------------------------------
echo "=== [7g] NICo REST helm chart ==="
_nico_registry_server="${NICO_IMAGE_REGISTRY%%/*}"
_nico_docker_cfg="$(printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}' \
    "${_nico_registry_server}" "${REGISTRY_PULL_USERNAME}" "${REGISTRY_PULL_SECRET}" \
    | base64 | tr -d '\n')"
helm upgrade --install nico-rest "${NICO_HELM_CHART}" \
    --namespace nico-rest \
    -f "${SCRIPT_DIR}/values/nico-rest.yaml" \
    --set global.image.repository="${NICO_IMAGE_REGISTRY}" \
    --set global.image.tag="${NICO_REST_IMAGE_TAG}" \
    --set "nico-rest-common.secrets.imagePullSecret.dockerconfigjson=${_nico_docker_cfg}" \
    --timeout 600s --wait
echo "NICo REST umbrella deployed"

# ---- 7h. NICo REST site-agent -----------------------------------------------
echo "=== [7h] NICo REST site-agent (site UUID: ${NICO_SITE_UUID}) ==="
NICO_SITE_AGENT_ARGS=(
    --namespace nico-rest
    -f "${SCRIPT_DIR}/values/nico-site-agent.yaml"
    --set global.image.repository="${NICO_IMAGE_REGISTRY}"
    --set global.image.tag="${NICO_REST_IMAGE_TAG}"
    --set "global.imagePullSecrets[0].name=image-pull-secret"
)

echo "Pre-applying NICo gRPC client certificate..."
helm template nico-rest-site-agent "${NICO_SITE_AGENT_CHART}" \
    "${NICO_SITE_AGENT_ARGS[@]}" \
    --show-only templates/certificate.yaml | kubectl apply -f -
kubectl annotate certificate/core-grpc-client-site-agent-certs -n nico-rest \
    "meta.helm.sh/release-name=nico-rest-site-agent" \
    "meta.helm.sh/release-namespace=nico-rest" --overwrite
kubectl label certificate/core-grpc-client-site-agent-certs -n nico-rest \
    "app.kubernetes.io/managed-by=Helm" --overwrite
kubectl wait --for=condition=Ready certificate/core-grpc-client-site-agent-certs \
    -n nico-rest --timeout=120s
echo "NICo gRPC client cert ready"

echo "Creating Temporal namespace for site ${NICO_SITE_UUID}..."
kubectl exec -n temporal deploy/temporal-admintools -- \
    sh -c "temporal operator namespace create -n '${NICO_SITE_UUID}' --address ${_TEMPORAL_ADDR} ${_TEMPORAL_TLS}" 2>/dev/null || true

helm upgrade --install nico-rest-site-agent "${NICO_SITE_AGENT_CHART}" \
    "${NICO_SITE_AGENT_ARGS[@]}" \
    --set "envConfig.CLUSTER_ID=${NICO_SITE_UUID}" \
    --set "envConfig.TEMPORAL_SUBSCRIBE_NAMESPACE=${NICO_SITE_UUID}" \
    --set "envConfig.TEMPORAL_SUBSCRIBE_QUEUE=site" \
    --set "envConfig.FLOW_GRPC_ENABLED=false" \
    --timeout 300s --wait
echo "NICo REST site-agent deployed (FLOW_GRPC_ENABLED=false)"

echo "Verifying site-agent NICo Core gRPC connection..."
_CONNECTED=false
for _i in $(seq 1 24); do
    _POD="$(kubectl get pods -n nico-rest -l "app.kubernetes.io/name=nico-rest-site-agent" -o name 2>/dev/null | head -1)"
    if [ -n "${_POD}" ] && kubectl logs -n nico-rest "${_POD}" --since=5m 2>/dev/null \
        | grep -q "NicoClient: successfully connected to server"; then
        _CONNECTED=true; echo "Site-agent connected to NICo Core gRPC"; break
    fi
    echo "  waiting for gRPC connection (${_i}/24)..."; sleep 5
done
if [ "${_CONNECTED}" = "false" ]; then
    echo "WARNING: gRPC connection unconfirmed — restarting site-agent for retry..."
    kubectl rollout restart statefulset/nico-rest-site-agent -n nico-rest
    kubectl rollout status statefulset/nico-rest-site-agent -n nico-rest --timeout=120s
fi

echo ""
echo "=== NICo REST v2.1.0-pr-14 install complete (Flow skipped — run deploy-flow.sh) ==="
kubectl -n nico-rest get pods

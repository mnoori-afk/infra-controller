#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# install-all.sh — single-command full NICo install for the nvcert GB300 NVL72 site.
#
# Wraps helm-prereqs/setup.sh (charts in-tree at origin/main) with the nvcert overlays and
# runs the WHOLE stack in one shot — nothing skipped:
#
#   Phases 1-5   infra: local-path, postgres-operator, MetalLB(+nvcert pools), cert-manager,
#                Vault (init+unseal), external-secrets, nico-prereqs (PKI, ESO, kvSeeds)
#   Phase 6      NICo Core (nico-system: api, dhcp, dns, pxe, ntp, unbound, ssh-console-rs)
#   Phase 7a-7g  NICo REST: CA issuer, REST postgres, Keycloak (dev IdP), Temporal (+TLS,
#                namespaces cloud/site/flow), nico-rest umbrella
#   Phase 7h     NICo Flow (flow/psm/nsm)
#   Phase 7i     site-agent + AUTOMATIC REST site registration (setup.sh resolves/mints the
#                site UUID, seeds the REST DB site row, and the chart bootstrap Job registers
#                and stores the OTP — no separate register-rest-site.sh needed)
#
# NOT installed here (post-steps, see README):
#   - Vault BMC credential seeding (VAULT-CREDS.md) + expected-machines load
#   - RMS (rack-manager) — separate chart, see launchpad-deploy/RMS-RUNBOOK.md
#   - admincli pod (nico/admincli-setup.sh)
#
# Usage:
#   export REGISTRY_PULL_SECRET='<NGC API key>'
#   SITE_NAME=<short-site-name> ./install-all.sh
#
# Env overrides (defaults are the launchpad-validated pins):
#   SITE_NAME             REQUIRED — short site identifier (also the REST site name)
#   NICO_IMAGE_REGISTRY   default nvcr.io/0837451325059433/carbide-dev
#   NICO_CORE_IMAGE_TAG   default v2.0.0-pr-503-g49a48a69d
#   NICO_REST_IMAGE_TAG   default v2.1.0-pr-14-g0d5452b9a   (REST + Flow share this line)
#   NICO_ORG              default ncx
#   AUTO_YES=true         skip the context confirmation prompt

set -euo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd "${_SELF_DIR}/.." && pwd)"
PREREQS="${REPO}/helm-prereqs"
CORE_VALUES="${_SELF_DIR}/nico/nico-core.nvcert.yaml"
METALLB_CONFIG="${_SELF_DIR}/nico/metallb-config.nvcert.yaml"

SITE_NAME="${SITE_NAME:-}"
export NICO_IMAGE_REGISTRY="${NICO_IMAGE_REGISTRY:-nvcr.io/0837451325059433/carbide-dev}"
export NICO_CORE_IMAGE_TAG="${NICO_CORE_IMAGE_TAG:-v2.0.0-pr-503-g49a48a69d}"
export NICO_REST_IMAGE_TAG="${NICO_REST_IMAGE_TAG:-v2.1.0-pr-14-g0d5452b9a}"
export NICO_ORG="${NICO_ORG:-ncx}"

# ---- guards ------------------------------------------------------------------
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${SITE_NAME}" ]] || fail "SITE_NAME is required (short site identifier, e.g. SITE_NAME=nvcert ./install-all.sh)"
[[ "${SITE_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "SITE_NAME must match [A-Za-z0-9][A-Za-z0-9._-]* (got '${SITE_NAME}')"
[[ -n "${REGISTRY_PULL_SECRET:-}" ]] || fail "export REGISTRY_PULL_SECRET='<NGC API key>' before running"
[[ -f "${CORE_VALUES}" ]]    || fail "core values not found: ${CORE_VALUES}"
[[ -f "${METALLB_CONFIG}" ]] || fail "metallb config not found: ${METALLB_CONFIG}"
command -v kubectl >/dev/null || fail "kubectl not found"
command -v helm >/dev/null    || fail "helm not found"

# No FILL_ME may survive in the core values (site domain, FNN/EVPN, etc. — README §0).
if grep -qE '^[^#]*FILL_ME' "${CORE_VALUES}"; then
    echo "ERROR: unresolved FILL_ME values in ${CORE_VALUES}:" >&2
    grep -nE '^[^#]*FILL_ME' "${CORE_VALUES}" >&2
    fail "fill them in first (README §0)"
fi

# boot-artifacts image must stay in lockstep with the Core tag (the forge-scout/forge-dpu
# agents ship from the boot-artifacts image, not the Core image).
_BA_TAG="$(grep -oE 'boot-artifacts-aarch64:[^"]+' "${CORE_VALUES}" | head -1 | cut -d: -f2 || true)"
if [[ -n "${_BA_TAG}" && "${_BA_TAG}" != "${NICO_CORE_IMAGE_TAG}" ]]; then
    echo "WARNING: boot-artifacts tag in nico-core.nvcert.yaml (${_BA_TAG}) != NICO_CORE_IMAGE_TAG (${NICO_CORE_IMAGE_TAG})." >&2
    echo "         Bump nico-pxe.bootArtifactContainers in the values file in lockstep with Core." >&2
fi

# ---- confirm cluster context ---------------------------------------------------
_CTX="$(kubectl config current-context 2>/dev/null || true)"
[[ -n "${_CTX}" ]] || fail "no kubectl context — tsh kube login <cluster> first"
echo "Kube context : ${_CTX}"
echo "Site name    : ${SITE_NAME}  (org ${NICO_ORG})"
echo "Core image   : ${NICO_IMAGE_REGISTRY}/nvmetal-carbide:${NICO_CORE_IMAGE_TAG}"
echo "REST/Flow    : ${NICO_IMAGE_REGISTRY}/nvmetal-carbide:${NICO_REST_IMAGE_TAG}"
if [[ "${AUTO_YES:-false}" != "true" ]]; then
    read -r -p "Deploy the FULL NICo stack to this cluster? [y/N] " _r
    [[ "${_r}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# ---- siteName into helm-prereqs/values.yaml ------------------------------------
# preflight.sh requires siteName in values.yaml (it feeds TMP_SITE into the postgres pods
# and the REST site name in phase 7i). Set it idempotently; leaves the tree dirty on
# purpose — the value is part of the deploy record.
if ! grep -qE "^siteName: [\"']?${SITE_NAME}[\"']?$" "${PREREQS}/values.yaml"; then
    sed -i.bak -E "s|^siteName:.*$|siteName: \"${SITE_NAME}\"|" "${PREREQS}/values.yaml"
    rm -f "${PREREQS}/values.yaml.bak"
    echo "Set siteName: \"${SITE_NAME}\" in helm-prereqs/values.yaml"
fi

# ---- strictARP — REQUIRED for MetalLB-L2 + kube-proxy IPVS (launchpad "Phase 4a") ----
# Without it every node answers ARP for the VIPs (kube-ipvs0 binds all Service IPs),
# fighting MetalLB's single-owner model -> VIPs flap. Idempotent check-then-patch.
if kubectl -n kube-system get cm kube-proxy -o jsonpath='{.data.config\.conf}' 2>/dev/null | grep -q "strictARP: false"; then
    echo "Enabling kube-proxy ipvs.strictARP (required for MetalLB-L2 + IPVS)..."
    kubectl -n kube-system get cm kube-proxy -o yaml \
        | sed 's/strictARP: false/strictARP: true/' | kubectl apply -f -
    kubectl -n kube-system rollout restart daemonset kube-proxy
    kubectl -n kube-system rollout status daemonset kube-proxy --timeout=180s
else
    echo "kube-proxy strictARP already true (or kube-proxy CM not found — verify manually if VIPs flap)."
fi

# ---- run the full setup ---------------------------------------------------------
# No --skip-rest / --skip-flow: Core + REST + Flow + site-agent all install, and
# phase 7i registers the REST site automatically (UUID minted or adopted by name).
cd "${PREREQS}"
./setup.sh -y \
    --core-values "${CORE_VALUES}" \
    --metallb-config "${METALLB_CONFIG}"

# ---- post-verify ----------------------------------------------------------------
echo ""
echo "==================================================================="
echo " nvcert install complete — verification"
echo "==================================================================="
kubectl get pods -n nico-system
kubectl get pods -n nico-rest
kubectl get pods -n flow
kubectl -n nico-system get svc -o custom-columns='NAME:.metadata.name,ETP:.spec.externalTrafficPolicy,VIP:.status.loadBalancer.ingress[0].ip' | grep -v '<none>' || true

SITE_UUID="$(kubectl get cm nico-rest-site-agent-config -n nico-rest -o jsonpath='{.data.CLUSTER_ID}' 2>/dev/null || true)"
echo ""
echo " REST site UUID : ${SITE_UUID:-<not found — check phase 7i output>}   <-- RECORD THIS"
echo ""
echo " Next steps (README 'After the install'):"
echo "   1. Seed Vault BMC credentials         (launchpad-deploy/VAULT-CREDS.md)"
echo "   2. admincli pod                       (nico/admincli-setup.sh)"
echo "   3. Load expected-machines             (nico/render.sh + admin-cli replace-all)"
echo "   4. Confirm switch DHCP relay is live  (NETWORKING.md 'DHCP Relay')"
echo "   5. RMS (rack-manager)                 (launchpad-deploy/RMS-RUNBOOK.md)"
echo "==================================================================="

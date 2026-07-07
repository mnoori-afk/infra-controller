#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# register-rest-site.sh — complete the NICo REST site setup for the launchpad GB300 site.
#
# The REST components (api, site-manager, site-agent, temporal, keycloak) are already deployed by
# install-rest-1.6.0.sh, but no `site` row exists in the REST DB, so `GET /v2/org/ncx/nico/site`
# returns empty and REST rack ingestion can't run. This script performs the SUPPORTED registration
# flow (mirrors rest-api/scripts/setup-local.sh, adapted for the live site):
#
#   1. mint a ProviderAdmin token   (Keycloak realm `nico`, client-credentials via `ncx-service`)
#   2. ensure an infrastructure-provider exists for org `ncx`
#   3. create the site               (POST /v2/org/ncx/nico/site -> new uuid + registrationToken/OTP)
#   4. create the site's Temporal namespace (= the new site id)
#   5. re-point the site-agent       (CLUSTER_ID + TEMPORAL_SUBSCRIBE_NAMESPACE + site-registration secret)
#   6. restart the site-agent and verify GET /site returns the site
#
# The API mints a NEW site uuid; the agent (currently pinned to the bootstrap 7f91b08b) is re-pointed
# to it. The old 7f91b08b Temporal namespace/CRD becomes orphaned (harmless).
#
# NO SECRETS IN THIS FILE. The ProviderAdmin token is minted by the blessed helper
# helm-prereqs/keycloak/get-token.sh (client_credentials on `ncx-service`, realm `nico`), which runs
# curl from INSIDE the cluster so the JWT `iss` matches the API's configured Keycloak URL. Overriding
# the token via env is supported: TOKEN=<jwt> ./register-rest-site.sh

set -euo pipefail

# ---- config (override via env) ----------------------------------------------
NS="${NS:-nico-rest}"
ORG="${ORG:-ncx}"
SITE_NAME="${SITE_NAME:-rg-forge-launchpad}"
SITE_DESC="${SITE_DESC:-GB300 NVL72 launchpad}"
TEMPORAL_NS="${TEMPORAL_NS:-temporal}"
API_LOCAL_PORT="${API_LOCAL_PORT:-8388}"
API="http://localhost:${API_LOCAL_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GET_TOKEN="${GET_TOKEN:-$(cd "${SCRIPT_DIR}/../.." && pwd)/helm-prereqs/keycloak/get-token.sh}"

need() { command -v "$1" >/dev/null || { echo "ERROR: '$1' not found" >&2; exit 1; }; }
need kubectl; need curl; need jq

# ---- 1. token (blessed in-cluster helper; correct issuer) --------------------------------
# ncx-service carries ncx:NICO_PROVIDER_ADMIN — the role POST /site requires.
if [ -z "${TOKEN:-}" ]; then
  echo "==> acquiring ProviderAdmin token via ${GET_TOKEN}"
  [ -x "$GET_TOKEN" ] || { echo "ERROR: $GET_TOKEN not found/executable (set GET_TOKEN or TOKEN)"; exit 1; }
  TOKEN=$("$GET_TOKEN")
fi
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "ERROR: no token"; exit 1; }
AUTH=(-H "Authorization: Bearer $TOKEN")

# ---- port-forward the API for the curl calls (token iss already correct) -----
PF_PIDS=()
cleanup() { for p in "${PF_PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT
echo "==> port-forwarding api :${API_LOCAL_PORT}"
kubectl -n "$NS" port-forward svc/nico-rest-api "${API_LOCAL_PORT}:8388" >/dev/null 2>&1 & PF_PIDS+=($!)
for i in $(seq 1 30); do curl -sf "$API/healthz" >/dev/null 2>&1 && break; sleep 1; done

# ---- 2. infrastructure-provider for org --------------------------------------
echo "==> ensuring infrastructure-provider for org '$ORG'"
PROV=$(curl -sf "$API/v2/org/$ORG/nico/infrastructure-provider/current" "${AUTH[@]}" 2>/dev/null || echo '{}')
PROV_ID=$(echo "$PROV" | jq -r '.id // empty')
if [ -z "$PROV_ID" ]; then
  PROV=$(curl -sf -X POST "$API/v2/org/$ORG/nico/infrastructure-provider" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -d '{"name":"Launchpad Provider","description":"rg-forge-launchpad GB300"}')
  PROV_ID=$(echo "$PROV" | jq -r '.id')
fi
echo "    provider id: $PROV_ID"

# ---- 3. create (or reuse) the site -------------------------------------------
echo "==> creating site '$SITE_NAME'"
EXIST=$(curl -sf "$API/v2/org/$ORG/nico/site" "${AUTH[@]}" 2>/dev/null || echo '[]')
SITE_ID=$(echo "$EXIST" | jq -r --arg n "$SITE_NAME" '(.items // . )[]? | select(.name==$n) | .id' 2>/dev/null | head -1)
if [ -n "${SITE_ID:-}" ] && [ "$SITE_ID" != "null" ]; then
  echo "    site already exists: $SITE_ID"
  OTP=$(curl -sf "$API/v2/org/$ORG/nico/site/$SITE_ID?renewRegistrationToken=true" "${AUTH[@]}" | jq -r '.registrationToken // empty')
else
  RESP=$(curl -sf -X POST "$API/v2/org/$ORG/nico/site" "${AUTH[@]}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$SITE_NAME\",\"description\":\"$SITE_DESC\",
         \"location\":{\"address\":\"\",\"city\":\"Santa Clara\",\"state\":\"CA\",\"country\":\"USA\",\"postalCode\":\"95054\"},
         \"contact\":{\"name\":\"Milad Noori\",\"email\":\"mnoori@nvidia.com\",\"phone\":\"\"}}")
  SITE_ID=$(echo "$RESP" | jq -r '.id')
  OTP=$(echo "$RESP" | jq -r '.registrationToken // empty')
fi
[ -n "$SITE_ID" ] && [ "$SITE_ID" != "null" ] || { echo "ERROR: site creation failed"; exit 1; }
echo "    SITE_ID=$SITE_ID  OTP.len=${#OTP}"

# ---- 4. Temporal namespace for the site --------------------------------------
echo "==> creating Temporal namespace $SITE_ID"
kubectl -n "$TEMPORAL_NS" exec deploy/temporal-admintools -- temporal operator namespace create --namespace "$SITE_ID" \
  --address temporal-frontend.temporal:7233 \
  --tls-cert-path /var/secrets/temporal/certs/server-interservice/tls.crt \
  --tls-key-path  /var/secrets/temporal/certs/server-interservice/tls.key \
  --tls-ca-path   /var/secrets/temporal/certs/server-interservice/ca.crt \
  --tls-server-name interservice.server.temporal.local || true

# ---- 5. re-point the site-agent ----------------------------------------------
echo "==> re-pointing site-agent to $SITE_ID"
kubectl -n "$NS" get cm nico-rest-site-agent-config -o yaml \
  | sed "s/CLUSTER_ID: .*/CLUSTER_ID: \"$SITE_ID\"/" \
  | sed "s/TEMPORAL_SUBSCRIBE_NAMESPACE: .*/TEMPORAL_SUBSCRIBE_NAMESPACE: \"$SITE_ID\"/" \
  | kubectl apply -f -

SMCA=$(kubectl -n "$NS" get secret site-manager-tls -o jsonpath='{.data.ca\.crt}' | base64 -d)
kubectl -n "$NS" delete secret site-registration --ignore-not-found
kubectl -n "$NS" create secret generic site-registration \
  --from-literal=site-uuid="$SITE_ID" \
  --from-literal=otp="${OTP:-}" \
  --from-literal=creds-url="https://nico-rest-site-manager:8100/v1/sitecreds" \
  --from-literal=cacert="$SMCA"

# ---- 6. restart + verify -----------------------------------------------------
echo "==> restarting site-agent"
kubectl -n "$NS" rollout restart sts/nico-rest-site-agent
kubectl -n "$NS" rollout status  sts/nico-rest-site-agent --timeout=240s

echo "==> verify: GET /v2/org/$ORG/nico/site"
curl -sf "$API/v2/org/$ORG/nico/site" "${AUTH[@]}" | jq '(.items // .)'
echo "DONE. SITE_ID=$SITE_ID"

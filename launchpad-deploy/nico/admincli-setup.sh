#!/usr/bin/env bash
# Stand up a durable `admincli` pod for the launchpad NICo cluster (Core-only, no REST/OIDC).
# Mints a ForgeAdminCLI mTLS client cert from Vault nicoca PKI (CN=admin-cli, OU=Invalid),
# stores it in secret admincli-cert, and deploys a long-lived pod (carbide image) with the cert
# + API URL preset. Mirrors the validated dev8 recipe (todos/admin-cli-access.md).
#
# nico-api already trusts this cert: our values set nico-api.auth.additionalIssuerCns: ["site-root"],
# and the Vault nicoca root CN is "site-root".
#
# Run:  KUBECONFIG=/Users/mnoori/go/src/stardrive/sites/launchpad/kubeconfig bash admincli-setup.sh
set -euo pipefail

NS=nico-system
IMAGE="nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:v2.0.0-pr-70-g7591be0f"
: "${KUBECONFIG:?export KUBECONFIG to the launchpad kubeconfig}"

echo "== 1. Vault root token =="
RT=$(kubectl -n vault get secret vaultroottoken -o jsonpath='{.data.token}' | base64 -d)
V(){ kubectl -n vault exec vault-0 -c vault -- sh -c "VAULT_SKIP_VERIFY=true VAULT_TOKEN=$RT VAULT_ADDR=https://127.0.0.1:8200 $1"; }

echo "== 2. Vault PKI role admin-cli (OU=Invalid, client cert, 1y) =="
V "vault secrets tune -max-lease-ttl=8760h nicoca" >/dev/null
V "vault write nicoca/roles/admin-cli allow_any_name=true enforce_hostnames=false cn_validations=disabled client_flag=true server_flag=false key_type=ec key_bits=256 ttl=8760h max_ttl=8760h ou=Invalid" >/dev/null

echo "== 3. Issue the client cert (valid 1y) =="
V "vault write -format=json nicoca/issue/admin-cli common_name=admin-cli ttl=8760h" > /tmp/lp-cli.json
python3 - <<'PY'
import json
d=json.load(open('/tmp/lp-cli.json'))['data']
open('/tmp/lp-cli.crt','w').write(d['certificate']+"\n")
open('/tmp/lp-cli.key','w').write(d['private_key']+"\n")
open('/tmp/lp-cli-ca.crt','w').write(d['issuing_ca']+"\n")
PY
openssl x509 -in /tmp/lp-cli.crt -noout -subject -enddate

echo "== 4. Store as secret admincli-cert =="
kubectl create secret generic admincli-cert -n "$NS" \
  --from-file=tls.crt=/tmp/lp-cli.crt --from-file=tls.key=/tmp/lp-cli.key --from-file=ca.crt=/tmp/lp-cli-ca.crt \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/lp-cli.json /tmp/lp-cli.crt /tmp/lp-cli.key /tmp/lp-cli-ca.crt

echo "== 5. Deploy durable admincli pod =="
kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admincli
  namespace: ${NS}
  labels: { app.kubernetes.io/name: admincli }
spec:
  replicas: 1
  selector: { matchLabels: { app.kubernetes.io/name: admincli } }
  template:
    metadata: { labels: { app.kubernetes.io/name: admincli } }
    spec:
      imagePullSecrets:
        - name: imagepullsecret
      containers:
        - name: admincli
          image: ${IMAGE}
          command: ["sleep", "infinity"]
          env:
            - { name: API_URL,          value: "https://nico-api.nico-system.svc.cluster.local:1079" }
            - { name: ROOT_CA_PATH,      value: "/etc/nico/certs/ca.crt" }
            - { name: CLIENT_CERT_PATH,  value: "/etc/nico/certs/tls.crt" }
            - { name: CLIENT_KEY_PATH,   value: "/etc/nico/certs/tls.key" }
          volumeMounts:
            - { name: cert, mountPath: /etc/nico/certs, readOnly: true }
      volumes:
        - name: cert
          secret: { secretName: admincli-cert }
YAML

kubectl rollout status deploy/admincli -n "$NS" --timeout=120s
echo "== done. Test:  kubectl exec -n ${NS} deploy/admincli -- /opt/carbide/carbide-admin-cli version =="

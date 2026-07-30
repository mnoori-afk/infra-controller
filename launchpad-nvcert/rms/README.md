# RMS (Rack Manager Service) — nvcert deploy

Deploys RMS `v0.9.0-dev1-116-g8e7aaf0` into the `rack-manager` namespace on the
nvcert GB300 cluster and wires it to NICo over mTLS. Mirrors the launchpad RMS deploy
(`launchpad-bringup/RMS/`), which the official runbook documents.

RMS is the gRPC **server**; NICo (nico-api) is the client and passes BMC endpoints +
credentials inline per RPC. RMS therefore has **no config.toml** — its entire runtime
config is these Helm values → CLI flags. The NICo-side `[rms]`/`[component_manager]`/
`[rack_profiles.NVL72_GB300]` TOML blocks live in `../nico/nico-core.nvcert.yaml` and are
already deployed in the live CM — no NICo restart is needed to pick up RMS.

## Files
| File | Purpose |
|---|---|
| `nvcert-values.yaml` | Helm values (image tag `v0.9.0-dev1-116-g8e7aaf0-amd64`, memory DB, mTLS on) |
| `rms-api-server-certificate.yaml` | cert-manager Certificate (vault-nico-issuer) → secret `rms-api-server-certificate` |

## Access
```bash
export KUBECONFIG=$HOME/.kube/launchpad-nvcert.config   # context nv-stg-dgxc.teleport.sh-launchpad-nvcert
```

## Steps (run manually)

### 1. Namespace + server cert + pull secret
```bash
kubectl create namespace rack-manager
kubectl apply -f launchpad-nvcert/rms/rms-api-server-certificate.yaml
kubectl -n rack-manager wait --for=condition=Ready certificate/rms-api-server-certificate --timeout=120s
# PULL SECRET — the v0.9.0-dev1-116-g8e7aaf0 image lives in the DSX mirror
# nvcr.io/0837451325059433/components-dev/rms-api (NOT nvidian/dcim, which caps at dev1-64).
# That org is served by the carbide-dev/components-dev-scoped secret == nico-system/imagepullsecret.
# Copy it into rack-manager under the name `imagepullsecret` (what the values reference):
kubectl -n nico-system get secret imagepullsecret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/rms-dcfg.json
kubectl -n rack-manager delete secret imagepullsecret --ignore-not-found
kubectl -n rack-manager create secret generic imagepullsecret \
  --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/tmp/rms-dcfg.json
rm -f /tmp/rms-dcfg.json
# The launchpad image_pull_secret_rms.yaml (nvidian/dcim) does NOT work for this build.
```

### 2. Vault policy — racks* paths (enables `cm update-firmware --access-token`)
Read the root token from `vault/vaultroottoken`, exec into `vault-0`, append to
`forge-vault-policy` (keep a .bak):
```
path "secrets/data/racks*"      { capabilities = ["create","read","patch","list","update","delete"] }
path "secrets/data/racks/*"     { capabilities = ["create","read","patch","list","update","delete"] }
path "secrets/metadata/racks*"  { capabilities = ["create","read","patch","list","update","delete"] }
path "secrets/metadata/racks/*" { capabilities = ["create","read","patch","list","update","delete"] }
```

### 3. Deploy
```bash
cd <rackmanagementservice>
git status --short          # working tree is dirty — stash/commit before checkout
git checkout 8e7aaf0        # v0.9.0-dev1-116-g8e7aaf0 → chart 0.9.0-dev.27 (matches the image)
helm upgrade --install rack-manager ./helm \
  -f <infra-controller-core>/launchpad-nvcert/rms/nvcert-values.yaml -n rack-manager
kubectl -n rack-manager get pods
kubectl -n rack-manager logs deploy/rms-api-server | head -25
#   expect: "gRPC server starting mode=mTLS port=8801"; in-memory + insecure-switch warns are expected
```

### 4. Verify mTLS to NICo
```bash
kubectl -n rack-manager logs deploy/rms-api-server | grep BatchGetPowerState
#   want status 200 / grpc 0, peer_identity="CN=nico-api.nico-system.svc.cluster.local"
kubectl -n nico-system logs deploy/nico-api --since=10m | grep -iE "rms|rack-manager:8801" | grep -i error   # none
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli rack list
```

## Follow-up (after RMS is healthy) — rack + NVLink switch ingestion
- POST expected-rack: org `ncx`, siteId `30b7f861-2b28-4da7-89b1-94d0e984457a`,
  rackProfileId `NVL72_GB300`, rackId **`nvcert-r1`**
- POST expected-switch per NVLink switch (9): BMC MACs from
  `../../launchpad-nvcert-docs/nvlink-management.md` — VERIFY against the ToR `bridge fdb show`
  first (on launchpad the portal MACs were wrong). NVOS `admin`/`Buynvidia2026!`,
  BMC `root`/`Buynvidia2026!`; patch nvos-mac-address per switch (admin-cli, bug workaround)
- POST expected-power-shelf (6): BMC `root`/`0penBmc`
- Then NVLink fabric bring-up → re-enable `forge_DcgmFullShort` in `../nico/nico-core.nvcert.yaml`

## Gotchas (all hit on launchpad)
1. `imagePullSecrets` must be a list of **maps** (`- name: imagepullsecret`), not strings — SSA rejects strings.
2. The pull secret must be **nvidian/dcim**-scoped; the nico-system one is carbide-dev → HTTP 401.
3. `[rms.tls]` subtable does NOT exist in the pr-503 NICo binary — use the flat
   `root_ca_path`/`client_cert`/`client_key`/`enforce_tls` keys (already correct in nico-core.nvcert.yaml).
4. Rack-profile name must be `NVL72_GB300` exactly, or nico-api refuses to boot (already correct).
5. `databaseMode: memory` → RMS loses state on restart (benign; NICo re-drives). The
   "unregistered node power state queried" log on a fresh start is expected.

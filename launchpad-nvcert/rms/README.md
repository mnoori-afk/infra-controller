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

## Rack component ingestion (materializes the rack → engages RMS)

State so far: RMS is deployed + healthy; the rack `nvcert-r1` exists as an `expected_rack`
(REST + Core), the 18 host machines are tagged `rack_id='nvcert-r1'`, but the `racks` row
is still empty and `rack show` says "No racks found". That's expected: the `racks` row is
created by **`ensure_rack_exists`**, which only fires when site-explorer *creates* a
component (switch / power-shelf / new host) carrying a `rack_id`. The already-created hosts
don't re-trigger it — **ingesting the switches + power shelves is the trigger.**

All hardware is verified in **`inventory.md`** (docs + ToR fdb + DHCP leases + BMC Redfish;
schema/creds confirmed against the working launchpad deploy). Ingest via admin-cli
(writes to Core `expected_switches`/`expected_power_shelves`, matching launchpad):

```bash
export KUBECONFIG=$HOME/.kube/launchpad-nvcert.config
cd launchpad-nvcert/rms

# validate a single switch first (schema/creds), then do the rest:
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli expected-switch add \
  --bmc-mac-address 20:4d:52:d8:87:fe --bmc-username root --bmc-password 'Buynvidia2026!' \
  --switch-serial-number MT2544602NNP \
  --nvos-mac-address 60:5e:65:97:97:5e --nvos-username admin --nvos-password 'Buynvidia2026!' \
  --rack_id nvcert-r1 --meta-name nvlink-switch-1 \
  --label site:nvcert --label rack:nvcert-r1 --label manufacturer:NVIDIA --label model:N5500_LD

# rack should now materialize:
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli rack show   # nvcert-r1

# then the remaining 8 switches + all 6 power shelves:
./ingest-rack-components.sh            # or: switches | shelves
```

Creds (verified): NVLink switch BMC `root`/`Buynvidia2026!`, NVOS `admin`/`Buynvidia2026!`;
power-shelf BMC `root`/`0penBmc` (NOT launchpad's password). NVOS MACs = `60:5e:65:*`
(docs; not DHCP-leased pre-ingestion, which is fine — NICo only needs the MAC to match).

### Verify + next
```bash
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"
$AC rack show ; $AC expected-switch show ; $AC expected-power-shelf show
kubectl -n rack-manager logs deploy/rms-api-server | grep BatchGetPowerState
#   want: status 200 / grpc 0, peer_identity="CN=nico-api.nico-system.svc.cluster.local"
```
Then NVLink fabric bring-up → re-enable `forge_DcgmFullShort` in `../nico/nico-core.nvcert.yaml`.

## Gotchas (all hit on launchpad)
1. `imagePullSecrets` must be a list of **maps** (`- name: imagepullsecret`), not strings — SSA rejects strings.
2. The pull secret must be **nvidian/dcim**-scoped; the nico-system one is carbide-dev → HTTP 401.
3. `[rms.tls]` subtable does NOT exist in the pr-503 NICo binary — use the flat
   `root_ca_path`/`client_cert`/`client_key`/`enforce_tls` keys (already correct in nico-core.nvcert.yaml).
4. Rack-profile name must be `NVL72_GB300` exactly, or nico-api refuses to boot (already correct).
5. `databaseMode: memory` → RMS loses state on restart (benign; NICo re-drives). The
   "unregistered node power state queried" log on a fresh start is expected.

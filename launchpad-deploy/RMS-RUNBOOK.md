# RMS enablement runbook — commands & config per side

End-to-end steps to make NICo drive rack/switch/power-shelf management through RMS on launchpad
(`rg-forge-launchpad`). Two sides: **RMS** (ns `rack-manager`) and **NICo** (ns `nico-system`). They meet over
gRPC **mTLS**, both certs signed by ClusterIssuer **`vault-nico-issuer`** (trust domain `nico.local`).

**Verified working:** `rms-api-server` logs `BatchGetPowerState` status 200,
`peer_identity="CN=nico-api.nico-system.svc.cluster.local"`, `node_type=powershelf_gb300_liteon`, `rack=launchpad-r1`.

Detail refs: RMS side → `../launchpad-bringup/RMS/README.md`; NICo side → `./RMS-ENABLEMENT.md`.
Access: `tsh kube login rg-forge-launchpad`.

---

## Side A — RMS (namespace `rack-manager`)

### A1. Namespace
```bash
kubectl create namespace rack-manager
```

### A2. RMS server cert from `vault-nico-issuer`
`kubectl apply -f` this Certificate (also the secret RMS mounts as its serving cert):
```yaml
# rms-api-server-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: rms-api-server-certificate, namespace: rack-manager }
spec:
  secretName: rms-api-server-certificate
  duration: 720h0m0s
  renewBefore: 360h0m0s
  privateKey: { algorithm: ECDSA, size: 384 }
  dnsNames: [ rms-api-server.rack-manager.svc.cluster.local ]
  uris:     [ spiffe://nico.local/rack-manager/sa/rms-api-server ]
  issuerRef: { group: cert-manager.io, kind: ClusterIssuer, name: vault-nico-issuer }
```
```bash
kubectl apply -f rms-api-server-certificate.yaml
kubectl -n rack-manager get certificate rms-api-server-certificate   # READY=True
```

### A3. Image pull secret (NGC token with `nvidian/dcim` access)
```bash
kubectl -n rack-manager create secret docker-registry imagepullsecret \
  --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password='<NGC_TOKEN>'
```
> The `nico-system/imagepullsecret` does NOT work here — it is scoped to org `carbide-dev`, not `nvidian/dcim` (401).

### A4. Helm install
From the RMS repo (`.../rackmanagementservice`), values = `../launchpad-bringup/RMS/launchpad-values.yaml`:
```bash
helm upgrade --install rack-manager ./helm -f helm/launchpad-values.yaml -n rack-manager
kubectl -n rack-manager get all      # rms-api-server 1/1 Running, svc :8801
```
**Key values** (`launchpad-values.yaml`):
```yaml
global:
  image: { tag: "v0.9.0-dev1-46-gc85b973-amd64", pullPolicy: Always }
  imagePullSecrets: [ { name: imagepullsecret } ]   # list of MAPS, not strings (else SSA rejects it)
databaseMode: memory                                # ephemeral; state lost on restart (dev)
apiServer:
  allowInsecure: false
  insecureSwitch: true                              # RMS↔switch unverified (dev)
  tls:
    enabled: true
    existingSecret: rms-api-server-certificate      # from A2
    caEnabled: true                                 # require client cert (mTLS)
```

### A5. Declare rack + components (REST v2)
```
POST /v2/org/ncx/nico/expected-rack          rack=launchpad-r1  profile=NVL72_GB300
POST /v2/org/ncx/nico/expected-switch        BMC root/Buynvidia2026!  NVOS admin
POST /v2/org/ncx/nico/expected-power-shelf   BMC root/0penBmc!
```

---

## Side B — NICo (namespace `nico-system`, Core `v2.0.0-pr-503`)

### B1. siteConfig changes
Source of truth: `nico/nico-core.launchpad.yaml` → `nico-api.nicoApiSiteConfig`. Adds/sets:
```toml
[site_explorer]
create_switches = true
create_power_shelves = true
explore_mode = "nv-redfish"          # required for GB300

[rack_profiles.NVL72_GB300]          # ⚠ NVL72_GB300, not NVL72_300 — typo makes nico-api refuse to boot
product_family = "gb300"
rack_hardware_topology = "gb300_nvl72r1_c2g4_topology"
# .rack_capabilities.compute  = { name=GB300, count=18, vendor=Lenovo }
# .rack_capabilities.switch   = { count=9,  vendor=NVIDIA }
# .rack_capabilities.power_shelf = { count=6, vendor=LiteOn }

[component_manager]
nv_switch_backend = "rms"
power_shelf_backend = "rms"
compute_tray_backend = "rms"
nv_switch_use_state_controller = true
power_shelf_use_state_controller = true
compute_tray_use_state_controller = true

[rms]                                # mTLS: FLAT paths (pr-503 has NO [rms.tls] subtable — it is ignored)
api_url = "https://rms-api-server.rack-manager.svc.cluster.local:8801"
enforce_tls = true
root_ca_path = "/var/run/secrets/spiffe.io/ca.crt"
client_cert  = "/var/run/secrets/spiffe.io/tls.crt"
client_key   = "/var/run/secrets/spiffe.io/tls.key"
```
No new mount needed: nico-api already mounts secret `nico-api-certificate` (also `vault-nico-issuer`) at
`/var/run/secrets/spiffe.io`. RMS's `--tls-ca` is the same CA → mTLS both ways.

### B2. Apply (CM patch + rollout — NOT `helm upgrade`)
The `nico` helm release is failed (SSA CM-ownership conflict) and nico-api has no `checksum/config`, so patch
the CM directly and roll the deployment:
```bash
# build /tmp/siteconfig-patch.json from nico-core.launchpad.yaml — write BOTH CM keys
#   (nico-api-site-config.toml AND carbide-api-site-config.toml)
kubectl -n nico-system get cm nico-api-site-config-files -o yaml > /tmp/nico-api-site-cm.bak.$(date +%s).yaml
kubectl -n nico-system patch cm nico-api-site-config-files --type merge --patch-file /tmp/siteconfig-patch.json
kubectl -n nico-system rollout restart deploy/nico-api
```
Expect clean parse (no `Invalid configuration`); `switch_controller`/`power_shelf_controller` start iterating.

---

## Verification
```bash
# RMS receiving NICo calls over mTLS
kubectl -n rack-manager logs deploy/rms-api-server | grep BatchGetPowerState   # 200, peer=CN=nico-api...

# NICo side
nico-admin-cli rack list                 # launchpad-r1  state=Created
nico-admin-cli managed-switch show       # switches state=ready
kubectl -n nico-system logs deploy/nico-api | grep -iE "rms|rack-manager:8801"  # no connect errors
```

## Prereqs (not RMS changes, but had to be healthy)
- Temporal/`postgres-0` scaled — `expected-rack/switch/power-shelf` declarations propagate REST → site-agent →
  Core via Temporal (`CreateExpectedRack` …). (The RMS mTLS gRPC call itself uses neither Flow nor Temporal.)
- Site registered: siteId `8c894583-bea4-445d-a5bd-46ee0e3cb3fb`, org `ncx`.
- NOT needed: REST v2.1 upgrade — RMS is driven by Core (pr-503), unchanged.

## Known remaining (rack-ingestion, not RMS-service)
- Switches 3/9 ready — some BMCs 401 → site-explorer latched `AvoidLockout`; fix creds then `site-explorer refresh <ip>`.
- LiteOn power-shelf BMCs fail generic Redfish probe ("BMC vendor field not populated"); managed via RMS path instead.

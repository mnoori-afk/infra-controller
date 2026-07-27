# nvcert — NICo Deploy Guide

GB300 NVL72 site. Branch `nvcert-launchpad-deployment` (rebased on `origin/main`, so the in-tree
Helm charts carry all current fixes), parallel to `launchpad-deploy/` (the launchpad site).
Architecture, networking rationale, and operational runbooks are identical — see `../launchpad-deploy/`.

**The entire stack installs with one command: `./install-all.sh`** (§2). It wraps
`helm-prereqs/setup.sh` with the nvcert overlays and installs infra + Core + REST + Flow +
site-agent, including automatic REST site registration. Nothing is skipped.

---

## 1. Fill these in before running anything

Everything else in the config files is already correct (VIPs, certs, rack profile, the 18 tray
BMC MACs). `install-all.sh` refuses to run while a `FILL_ME` survives in the core values.

### 1.1 Site name and domain ⚠️ REQUIRED

Ask the team what they called this cluster (the Teleport kube-login name is the canonical answer).

| Field | File | What to set |
|---|---|---|
| `SITE_NAME` env | `install-all.sh` invocation | short name, e.g. `nvcert` — becomes the REST site name + postgres TMP_SITE |
| `nico-api.hostname` | `nico/nico-core.nvcert.yaml` | `api-<name>.nvidialaunchpad.internal` |
| `certificate.extraDnsNames[0]` | `nico/nico-core.nvcert.yaml` | same as hostname |
| `sitename` | `nico/nico-core.nvcert.yaml` (siteConfig TOML) | `rg-forge-<name>` |
| `initial_domain_name` | `nico/nico-core.nvcert.yaml` (siteConfig TOML) | `<name>.nvidialaunchpad.internal` |

**Why it matters:** `hostname` / `extraDnsNames` go into the nico-api TLS cert — wrong value =
agents and DPUs fail TLS SAN verification.

### 1.2 FNN/EVPN values — from the network team (Brian / Jasmeer)

Seeded with launchpad values so nico-api starts cleanly; dormant in NIC mode
(`route_servers = []`). Update before enabling DPU mode:

| Field | Launchpad value (reference) |
|---|---|
| `datacenter_asn` | `32325` |
| `site_global_vpc_vni` | `245002` |
| `site_fabric_prefixes` | `["172.16.4.128/25"]` |
| `[fnn.admin_vpc] vpc_vni` | `60300` |
| route_target ASNs in `[fnn.routing_profiles.*]` | 32325–32329 |
| `[pools.fnn-asn]` range | `4268000000–4268000099` |

### 1.3 Switch DHCP relay — from the network team

The mgmt switches must relay tray-BMC DHCP to the nico-dhcp VIP `172.16.2.41` (ip-helper).
Any giaddr inside `172.16.2.0/24` works — NICo matches by subnet membership, not exact gateway.
See §"DHCP relay" below for the temporary node-hosted fallback if the switch relay isn't ready.

---

## 2. Install — one command

```bash
tsh kube login <nvcert-cluster-name>        # correct context is checked by the script
export REGISTRY_PULL_SECRET='<NGC API key>' # write-scoped key for nvcr.io/0837451325059433
cd <repo>/launchpad-nvcert

SITE_NAME=<short-site-name> ./install-all.sh
```

That runs, in order (all phases of `helm-prereqs/setup.sh`, no skips):

| Phase | What |
|---|---|
| 1–5 | local-path, postgres-operator, **MetalLB** (+ nvcert VIP pools), cert-manager, **Vault** (init+unseal), external-secrets, nico-prereqs (PKI, ESO, kvSeeds) |
| 6 | **NICo Core** — api, dhcp, dns, pxe, ntp, unbound, ssh-console-rs (VIPs `.40–.49`) |
| 7a–7g | **NICo REST** — CA issuer, REST postgres, Keycloak dev IdP, Temporal (+TLS, namespaces `cloud`/`site`/`flow`), nico-rest umbrella |
| 7h | **NICo Flow** — flow/psm/nsm |
| 7i | **site-agent** + automatic REST **site registration** — setup.sh mints (or adopts) the site UUID, seeds the REST DB row, and the chart's bootstrap Job registers and stores the OTP. `FLOW_GRPC_ENABLED=true` from the start. |

The script prints the minted **REST site UUID** at the end — record it. Re-runs are idempotent
(the UUID is re-adopted from the site-agent ConfigMap / DB row by name).

Image tags default to the launchpad-validated pins (overridable via env):

| Component | Default tag |
|---|---|
| NICo Core (`nvmetal-carbide`) | `v2.0.0-pr-503-g49a48a69d` |
| boot-artifacts (aarch64 PXE) | `v2.0.0-pr-503-g49a48a69d` (pinned in the values file — keep in lockstep with Core) |
| NICo REST / Flow / site-agent | `v2.1.0-pr-14-g0d5452b9a` |

> The Temporal-postgres sizing fix (4Gi/2cpu — the launchpad site-pairing unblocker) is already
> in-tree on main (`rest-api/deploy/kustomize/base/postgres/statefulset.yaml`); no manual patch.

`install-all.sh` also enables **kube-proxy `ipvs.strictARP`** before setup.sh — a hard
requirement for MetalLB-L2 + IPVS (without it every node answers ARP for the VIPs and they
flap). If NICo was brought up some other way, verify it manually — see `NETWORKING.md`
§"strictARP is REQUIRED".

---

## 3. After the install

### 3.1 Vault credentials — two separate seeds, both are ingestion gates

1. **BMC root credential** (site-wide) — `admin / <tray BMC password>` per
   `../launchpad-deploy/VAULT-CREDS.md`. Without it, site-explorer's Redfish probes fail
   every cycle.
2. **UEFI `site_default` passwords** — the install seeds these Vault paths **with BLANK
   passwords** (see `helm-prereqs/values.yaml` kvSeeds); the operator must populate them
   per site or preingestion logs `Missing credential machines/all_{hosts,dpus}/site_default/uefi-metadata-items/auth`:
   - `secrets/machines/all_hosts/site_default/uefi-metadata-items/auth`
   - `secrets/machines/all_dpus/site_default/uefi-metadata-items/auth`

### 3.2 admincli pod
```bash
bash nico/admincli-setup.sh
```

### 3.3 DpuMode hardware prerequisites (do before expected-machines)

These trays are set to `DpuMode` — the BlueField-3 manages host networking. Two hardware
steps must be done **before** site-explorer can link them:

**a. Power on all DPU BMCs** (BlueField OpenBMC, separate from the tray AMI MegaRAC).
DPU BMCs also get DHCP leases from the `.50-.250` pool. Confirm they have IPs before loading
expected-machines.

**b. If any BlueField is currently in NIC mode, switch it to DPU mode + reset:**
```bash
# On the host OS of the affected tray (run once per tray that was in NIC mode):
mlxfwreset -d /dev/mst/mt41692_pciconf0 -l 4 r
# Then power-cycle the tray (the BlueField needs a cold reboot to apply the mode change).
```

**c. Populate `fallback_dpu_serial_numbers` in the template (GB300 Lenovo-specific):**
The GB300 Lenovo host BMC returns `null` for the BlueField `NetworkAdapter.SerialNumber`.
Without a serial override, site-explorer always logs `"sees no DPUs on this host"` and
leaves the machine Unlinked. Get the DPU serial for each tray from the DPU BMC:
```bash
# From a CP node, for each DPU BMC IP (e.g. 172.16.2.XX):
curl -sk -u root:<dpu-bmc-password> \
  https://172.16.2.XX/redfish/v1/Systems/Bluefield | python3 -m json.tool | grep SerialNumber
# Or from the host BMC:
curl -sk -u admin:<tray-bmc-password> \
  https://172.16.2.YY/redfish/v1/Chassis/Riser_Slot1_BlueField_3_SmartNIC_Main_Card | python3 -m json.tool | grep SerialNumber
```
Then patch each expected-machine entry (or edit the template and reload):
```bash
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"
$AC expected-machine patch --bmc-mac-address <TRAY_BMC_MAC> \
    --fallback-dpu-serial-number <DPU_SERIAL>
```
Repeat for all 18 trays. Without this, no tray will progress past Unlinked in DpuMode.
Full analysis: `../launchpad-bringup/DPU-HOST-ASSOCIATION.md`.

### 3.4 Expected-machines seed (the ingestion gate)
```bash
export BMC_PASSWORD='<tray BMC password from Vault>'
bash nico/render.sh       # → nico/expected_machines.nvcert.json  (git-ignored)
kubectl -n nico-system exec -i deploy/admincli -- \
  /opt/carbide/carbide-admin-cli expected-machine replace-all \
  < nico/expected_machines.nvcert.json
```
Chassis serials are `serial-pending-tray-N` placeholders — site-explorer learns them on first contact.
After loading, patch each tray's `fallback-dpu-serial-number` (§3.3c above) — this is the
**critical step** for DpuMode ingestion on GB300 Lenovo hardware.

### 3.4 Verify the network path: VIPs → DNS → DHCP → ingestion

In order — each layer depends on the previous one:

```bash
# 1. VIPs answer ARP (L2 mode — no BGP; see NETWORKING.md §arping for the full loop + caveats)
arping -c 1 -I bond0 172.16.2.40    # from a CP node that doesn't own the VIP

# 2. .forge DNS resolves via unbound
nslookup carbide-pxe.forge 172.16.2.42
nslookup carbide-api.forge 172.16.2.42

# 3. Switch DHCP relay is delivering (leases appear once trays power on; §1.3)
kubectl -n nico-system logs deploy/nico-dhcp -f | grep -i lease

# 4. Ingestion — expected machines get discovered by site-explorer
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli machine list
```

**If trays get leases + PXE but stall in `WaitingForDiscovery`** (the launchpad GB300 wall):
1. Both `.43` pxe services must be ETP=**Local** (`kubectl -n nico-system get svc | grep pxe`) —
   a `<pending>` EXTERNAL-IP means the MetalLB shared-VIP wedge: restart `metallb-controller`.
2. `deny_prefixes` must be `[]` in the siteConfig (denying the mgmt underlay blocks the VIPs).
3. On GB300 the tray host reaches the network THROUGH the BlueField-3: its HBN OVS bridge
   (`br-hbn`, table 15) can drop host→`172.16.2.0/24` traffic so scout never reaches
   nico-api/pxe. Check from the DPU: `ovs-ofctl dump-flows br-hbn | grep 172.16.2` — launchpad
   worked around it with an ovs-ofctl allow rule for `172.16.2.0/24`; the proper fix is with
   the forge-dpu team (Brian).
4. Verify scout can resolve + reach `carbide-api.forge` (.40) and `carbide-pxe.forge` (.43)
   from a tray console (`nico-ssh-console-rs`, VIP .49).

### 3.5 RMS (rack-manager)
Separate chart, namespace `rack-manager`. NICo Core is already configured for it
(`[rms]` mTLS + `[component_manager]` backends in the siteConfig) — state controllers retry until
RMS exists. See `../launchpad-deploy/RMS-ENABLEMENT.md` + `RMS-RUNBOOK.md`.

### 3.6 ssh-console-rs check
Ships with Core at VIP `.49`; config is in the values file (fleet-wide nvcert CA fingerprint +
`swngc-forge-admins` role). After ANY config change:
`kubectl -n nico-system rollout restart deploy/nico-ssh-console-rs` (chart has no config checksum).
Playbook: `../launchpad-deploy/SSH-CONSOLE.md`.

---

## 4. Hardware reference

**13 control-plane nodes** — cp-1/2/3 are k8s masters, cp-4 through cp-13 are workers.

| Node | k8s role | Static IP | BMC IP |
|---|---|---|---|
| cp-1 | master | 172.16.2.11 | 172.16.0.28 |
| cp-2 | master | 172.16.2.12 | 172.16.0.29 |
| cp-3 | master | 172.16.2.13 | 172.16.0.30 |
| cp-4 … cp-13 | worker | 172.16.2.14–.23 | 172.16.0.31–.40 |

**18 compute trays** (Grace + BlueField-3, NIC mode) — BMC MACs pre-populated in
`nico/expected_machines.nvcert.template.json`.

**`172.16.2.0/24` carve** (VLAN 200): node statics `.11–.23` · MetalLB VIPs `.40–.49` ·
DHCP lease pool `.50–.250` (fenced by `reserve_first = 50`).

| Service | VIP | | Service | VIP |
|---|---|---|---|---|
| nico-api | .40 (ETP=Local) | | nico-ntp ×3 | .44 / .45 / .46 |
| nico-dhcp (kea) | .41 | | nico-dns ×2 | .47 / .48 |
| unbound DNS | .42 | | nico-ssh-console-rs | .49 |
| nico-pxe | .43 (ETP=Local, shared) | | | |

Full networking design: `NETWORKING.md` (this dir) + `../launchpad-deploy/NETWORKING.md`.

---

## 5. DHCP relay — switch-hosted (standard), node-hosted (fallback)

**Standard:** the mgmt switches relay BMC DHCP to VIP `.41` (§1.3). giaddr = switch SVI —
launchpad sees `.4`/`.5`. NICo matches giaddr by subnet membership (`ip <<= prefix`), so any
`172.16.2.x` source works. **kea can schedule on any node — no anti-affinity needed.**

**Fallback (bring-up only, no networking-team dependency):** run `isc-dhcp-relay` on cp-1
(`SERVERS=172.16.2.41 INTERFACES=bond0 OPTIONS=-4`) — full steps in
`../launchpad-deploy/DHCP-RELAY.md` §4.

> ⚠️ Fallback-only rule: with a node-hosted relay, pin kea OFF the relay node
> (`kubectl -n nico-system patch deploy nico-dhcp` with NodeAffinity `NotIn: [<relay-node>]`) —
> a relay forwarding to a VIP backed by a same-node pod goes deaf (real launchpad outage).
> Lift the pin when the switch relay takes over (launchpad did on 2026-06-24).

---

## 6. Operational rules

- **ssh-console-rs stale pod** — always `rollout restart deploy/nico-ssh-console-rs` after a
  config change; no checksum annotation. Symptom: `openssh certificate CA certificate not trusted`.
- **Rolling the Core image** — migrate the DB first, then roll workloads; and bump the
  boot-artifacts image in lockstep (agents ship from it). See `../launchpad-deploy/README.md §10`.
- **Healing a stuck `nico` release (Helm 4)** — field-ownership conflicts from a prior
  `kubectl edit`: `helm upgrade … --force-conflicts` (diff render-vs-live first);
  `--take-ownership` for ownership-metadata errors. See `../launchpad-deploy/README.md §12`.
- **site-agent OTP expiry** — if the site sits unpaired >24h, roll a fresh OTP:
  `../launchpad-deploy/README.md §4`.
- **nico-api config changes** — no config reloader: `rollout restart deploy/nico-api` after any
  siteConfig CM change (`../launchpad-deploy/CONFIG-GUIDE.md`).

---

## 7. What's in this directory

| File | What it is |
|---|---|
| `install-all.sh` | **The installer** — single command, full stack (wraps `helm-prereqs/setup.sh`, no skips) |
| `nico/nico-core.nvcert.yaml` | NICo Core Helm values — networking, VIPs, rack profile, RMS mTLS, ssh-console |
| `nico/metallb-config.nvcert.yaml` | MetalLB L2 pools: external `.40`, internal `.41–.49` |
| `nico/expected_machines.nvcert.template.json` | 18 tray BMC MACs; render with `render.sh` |
| `nico/render.sh` | Substitutes `$BMC_PASSWORD` → `expected_machines.nvcert.json` (git-ignored) |
| `nico/admincli-setup.sh` | Mints admincli mTLS cert from Vault + deploys durable pod |
| `netplan/cp-{1,2,3}_00-installer-config.yaml` | Static OS netplan for the 3 k8s masters |
| `NETWORKING.md` | nvcert subnet carve, VIP map, DHCP relay design |

Removed vs. launchpad: `install-rest.sh`, `register-rest-site.sh`, and `deploy-flow.sh` are
superseded — `setup.sh` (main) installs REST/Flow in-tree and registers the site automatically
in phase 7i. For a solo Flow redeploy on a live cluster, adapt `../launchpad-deploy/nico/deploy-flow.sh`.

---

## 8. Reference docs (same architecture as launchpad)

| Topic | Doc |
|---|---|
| Network design, MetalLB, DHCP relay history | `../launchpad-deploy/NETWORKING.md`, `DHCP-RELAY.md` |
| Vault BMC/UEFI credentials | `../launchpad-deploy/VAULT-CREDS.md` |
| siteConfig change guide | `../launchpad-deploy/CONFIG-GUIDE.md` |
| Admin CLI | `../launchpad-deploy/ADMIN-CLI.md` |
| Flow gotchas (historical) | `../launchpad-deploy/FLOW-FIXES.md` |
| RMS deployment | `../launchpad-deploy/RMS-ENABLEMENT.md`, `RMS-RUNBOOK.md` |
| Rack + component-manager config | `../launchpad-deploy/nico/RACK-CONFIG.md` |
| ssh-console-rs playbook | `../launchpad-deploy/SSH-CONSOLE.md` |
| Full launchpad deploy record | `../launchpad-deploy/README.md` |

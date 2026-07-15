# Launchpad — changing the carbide siteConfig & other configs

How to change NICo's configuration on launchpad: the carbide **siteConfig TOML** (networks, prefixes,
route servers, DHCP), the **helm values**, the **image tag**, and **per-host** settings. Two distinct
"layers" — know which one you're editing.

> `launchpad-deploy/` is the git-tracked deploy source-of-truth (branch `launchpad-deployment`);
> `launchpad-bringup/` is the gitignored live-truth working copy. On drift, **live is correct** —
> reconcile this folder to match live.

---

## The two config layers

| Layer | Source of truth | How it reaches the cluster | When to use |
|---|---|---|---|
| **Helm values** (`nico/nico-core.launchpad.yaml`, `nico/metallb-config.launchpad.yaml`) | this folder | `helm upgrade` (or `setup.sh`) renders them into the `nico` release | the *declarative* way; survives re-installs |
| **Live configmap** (`nico-api-site-config-files` in nico-system) | the cluster | edit the cm + restart nico-api | a *fast/live* tweak; **gets overwritten on the next helm upgrade**, so mirror it back into the value file |

The carbide **siteConfig TOML** appears in BOTH: as the `siteConfig:` block in
`nico-core.launchpad.yaml`, and rendered live into the configmap keys
`carbide-api-site-config.toml` + `nico-api-site-config.toml`.

### Other config layers
- Flow config → [FLOW-FIXES.md](FLOW-FIXES.md).
- RMS / rack siteConfig → [nico/RACK-CONFIG.md](nico/RACK-CONFIG.md) + [RMS-ENABLEMENT.md](RMS-ENABLEMENT.md).
- ssh-console-rs → [SSH-CONSOLE.md](SSH-CONSOLE.md).

Because the `nico` helm release was healed and nico-api has **no `checksum/config`**, siteConfig CM changes
are applied then followed by `kubectl -n nico-system rollout restart deploy/nico-api` (they do NOT
auto-restart).

---

## A. Change the carbide siteConfig TOML

### Option 1 — declarative (preferred): edit the value file, helm upgrade
1. Edit the `siteConfig` block in `nico/nico-core.launchpad.yaml`.
2. Re-render:
   ```bash
   cd <repo>/helm-prereqs
   helm upgrade nico ../helm/<nico-core-chart> -n nico-system \
     -f ../launchpad-deploy/nico/nico-core.launchpad.yaml \
     --set global.image.repository=nvcr.io/0837451325059433/carbide-dev \
     --set global.image.tag=v2.0.0-pr-503-g49a48a69d --reuse-values
   ```
   (nico-api restarts and reloads the new siteConfig.)

### Option 2 — live (fast, for a one-off): edit the configmap + restart
Reconcile this folder to match live afterward (live is source-of-truth). Trays DHCP on
`[networks.launchpad-mgmt]` (`172.16.2.0/24`); `[networks.admin]` (`172.16.4.0/25`, `reserve_first=5`) is
a placeholder that never allocates in NIC mode.
```bash
CM=nico-api-site-config-files
# example: patch a value in BOTH toml keys at once
kubectl -n nico-system get cm $CM -o yaml \
 | sed 's#<old-value>#<new-value>#g' \
 | kubectl apply -f -
kubectl -n nico-system rollout restart deploy/nico-api      # reload siteConfig
```
nico-api **reads siteConfig only at startup** — you must restart it for cm edits to take effect. Because
the healed `nico` release's nico-api has **no `checksum/config`**, cm changes do **not** auto-restart it;
the `rollout restart` is mandatory.

### The siteConfig knobs that matter on launchpad
```toml
enable_route_servers = false                 # NIC-mode / no overlay -> no BGP route servers
site_fabric_prefixes = ["172.16.4.128/25"]    # N-S tenant fabric (underlay)
# deny_prefixes emptied on launchpad (live is source-of-truth); do NOT deny the mgmt underlay
# 172.16.2.0/24 — it holds the reachable VIPs:
deny_prefixes = []

[networks.admin]        # placeholder — admin NEVER allocates in NIC mode.
type = "admin"; prefix = "172.16.4.0/25"; gateway = "172.16.4.1"; reserve_first = 5

[networks.launchpad-mgmt]   # VLAN 200 — trays DHCP here. BMC/host-OOB discovery. site-explorer ONLY scans underlay segments.
type = "underlay"; prefix = "172.16.2.0/24"; gateway = "172.16.2.1"
reserve_first = 50          # fences SC statics .11-.13 + MetalLB VIPs .40-.49 off the lease pool (.50-.250)

[networks.launchpad-ns]     # N-S data underlay (tenant fabric)
type = "underlay"; prefix = "172.16.3.0/24"; gateway = "172.16.3.1"; reserve_first = 2
```
Rules of thumb:
- Adding/resizing a network: don't overlap `site_fabric_prefixes`. `deny_prefixes = []` on launchpad —
  do NOT re-add the mgmt underlay `172.16.2.0/24` (it holds the reachable VIPs).
- `dhcp_servers` must be the nico-dhcp VIP (`172.16.2.41`).
- `[networks.<x>] type=underlay` is required for site-explorer to scan a segment (it only scans underlays).

---

## B. Change the image tag (Core)
- Declarative: it's passed via `--set global.image.tag=...` (not hard-coded in the value file — the file
  leaves `image.tag: ""`). Change the tag in your helm upgrade / `NICO_CORE_IMAGE_TAG`.
- Live roll (DHCP-safe): see **README §6** (migrate DB first, cordon cp-1, `set image` all carbide
  workloads, verify dhcp off cp-1, uncordon).

## C. Change MetalLB VIPs / service IPs
Edit `nico/metallb-config.launchpad.yaml` (the `IPAddressPool` `172.16.2.30–.49`) and the per-service
`externalService` VIPs in `nico-core.launchpad.yaml`. VIP pool and the DHCP lease pool must not overlap
(that's what `reserve_first=50` on `launchpad-mgmt` enforces).

## D. Per-host settings (expected-machines) — live, no restart
`expected-machine patch` is partial + live (applies on the next ~30s explore cycle):
```bash
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"
# DPU mode: dpu-mode (default) | nic-mode (DPU as plain NIC) | no-dpu (ignore DPU)
$AC expected-machine patch --bmc-mac-address <MAC> --dpu-mode dpu-mode
# DPF: not deployed here -> keep disabled
$AC expected-machine patch --bmc-mac-address <MAC> --dpf-enabled false
# fix a serial mismatch (clears SerialNumberMismatch health alert):
$AC expected-machine patch --bmc-mac-address <MAC> --chassis-serial-number <SERIAL>
# DPU serial override when the host BMC doesn't report the DPU's NIC serial:
$AC expected-machine patch --bmc-mac-address <MAC> --fallback-dpu-serial-number <DPU_SERIAL>
```
To re-ingest after changing per-host settings: `machine force-delete --machine <id>` (omit `-d` to avoid a
kea redeploy / DHCP blip), they re-create on the next explore cycle.

## E. NICo REST config
Edit `helm-prereqs/values/nico-rest.yaml` (Keycloak/auth, replica counts) and re-run
`install-rest-1.6.0.sh`, or `helm upgrade nico-rest`. The site UUID is pinned in the script — keep it stable.

---

## Quick "where do I change X?" index
| Want to change… | Edit | Apply |
|---|---|---|
| network prefix / gateway / reserve_first / deny / route-servers | `nico-core.launchpad.yaml` `siteConfig` (or live cm) | helm upgrade (or cm + restart nico-api) |
| Core image tag | `--set global.image.tag` / `NICO_CORE_IMAGE_TAG` | helm upgrade / `set image` (README §6) |
| service VIPs / MetalLB pool | `metallb-config.launchpad.yaml` + `nico-core.launchpad.yaml` | helm upgrade |
| a tray's dpu-mode / DPF / serials | `expected-machine patch` | live (~30s) |
| REST auth / replicas | `helm-prereqs/values/nico-rest.yaml` | `install-rest-1.6.0.sh` / helm upgrade |
| DHCP relay target / option-6 nameserver | `nico-core.launchpad.yaml` dhcp hookParameters | helm upgrade |

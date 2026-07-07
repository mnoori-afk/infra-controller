# Phase 4 — NICo Core deployment + GB300 tray ingestion (launchpad)

Cluster is up (kubespray, v1.30.4, Calico) and in Teleport (`tsh kube login rg-forge-launchpad`).
Scope: **NICo Core only** (`--skip-rest --skip-flow`). Boot artifacts: **aarch64** (Grace host + BF3 DPU).
Full design in `../../../.claude/plans/...` and RUNBOOK §8. Files here: `metallb-config.launchpad.yaml`,
`expected_machines.launchpad.json`, plus the `nico-core.yaml` fills below.

KUBECONFIG: `export KUBECONFIG=/Users/mnoori/go/src/stardrive/sites/launchpad/kubeconfig` (or `tsh kube login rg-forge-launchpad`).

## VIP map (172.16.2.0/24, MetalLB L2, pool .30–.49; DHCP lease pool .50–.250)
| Service | VIP | | Service | VIP |
|---|---|---|---|---|
| nico-api | 172.16.2.40 | | nico-ntp 0/1/2 | .44/.45/.46 |
| nico-dhcp | 172.16.2.41 | | nico-dns 0/1 | .47/.48 |
| unbound | 172.16.2.42 | | nico-ssh-console | .49 |
| nico-pxe | 172.16.2.43 | | | |

## 4a — Pre-NICo cluster prep
```bash
# MetalLB L2 needs strictARP under ipvs:
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/strictARP: false/strictARP: true/' | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
# Nodes schedulable (no NoSchedule taint):
kubectl get nodes -o json | jq '.items[]|{name:.metadata.name,taints:.spec.taints}'
# Sysctls on each node (NICo preflight checks these):
for n in 1 2 3; do tsh ssh launchpad-control-plane-$n 'echo -n "$(hostname): "; sudo sysctl -n net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward | tr "\n" " "; echo'; done
```

## 4b — Fill values + install NICo Core
1. Copy `metallb-config.launchpad.yaml` → `helm-prereqs/values/metallb-config.yaml`.
2. Edit `helm-prereqs/values.yaml`: `siteName: rg-forge-launchpad`; postgres 3× / local-path-persistent;
   `vault.kvSeeds` BMC/UEFI creds (tray BMC admin/Buynvidia2026!, DPU BMC root/Buynvidia2026!).
3. Edit `helm-prereqs/values/nico-core.yaml` (see checklist `nico-core.fills.md`): hostname + VIPs +
   siteConfig TOML (admin 172.16.2.0/24 reserve_first=50, underlay 172.16.3.0/24, dhcp_servers=[.41],
   deny_prefixes, firmware autoupdate=false), kea hookParameters (.42/.44-.46/.43), bootArtifactContainers
   = aarch64 image only (`cp -r /aarch64 /apt ...`), unbound localData → VIPs + upstream forwarder.
4. Install:
```bash
cd /Users/mnoori/Desktop/AgeSS/infra-controller-core/helm-prereqs
export NICO_IMAGE_REGISTRY=<registry> NICO_CORE_IMAGE_TAG=<tag> REGISTRY_PULL_SECRET=<ngc-key>
./preflight.sh --skip-rest --skip-flow
./setup.sh --skip-rest --skip-flow -y
kubectl -n nico-system get pods,svc        # all Running; VIPs .40–.49 assigned
```

## 4c — .forge DNS + DHCP relay (network side)
```bash
nslookup carbide-api.forge 172.16.2.42      # -> 172.16.2.40
nslookup carbide-pxe.forge 172.16.2.42      # -> 172.16.2.43
```
- Have networking configure the **core-switch VLAN-200 DHCP relay (giaddr 172.16.2.1) → 172.16.2.41**.
  This is MANDATORY — Kea rejects non-relayed packets.

## 4d — Seed expected_machines + ingest
1. Fill `expected_machines.launchpad.json` for all 18 trays (MACs from compute-trays.md; serials via Redfish;
   confirm host-BMC-MAC for NIC mode). Load via admin-cli/API.
2. Ensure BMC/UEFI creds in Vault (site-wide root + per-BMC).
3. Power trays; watch:
```bash
kubectl -n nico-system logs deploy/nico-api --since=5m | grep -iE 'discover|state=|dhcp'
kubectl -n nico-system logs deploy/nico-pxe --since=5m | grep -iE 'aarch64|ipxe|scout|bfb'
ac -f json mh show     # trays progress HostInit -> BomValidating -> Ready
```

## Verify (done when)
- All nico-system pods Running, VIPs .40–.49 bound.
- `.forge` names resolve to VIPs via unbound.
- A tray DHCPDISCOVER reaches nico-dhcp (relay giaddr 172.16.2.1 → admin segment) and PXE-boots aarch64.
- Trays reach `Ready`.

## Open / supply-before-run
- NICO_IMAGE_REGISTRY + Core tag + NGC pull secret; unbound + boot-artifacts-aarch64 image tags.
- nico-api.hostname / initial_domain_name; unbound upstream resolver IP.
- Core-switch DHCP relay (networking/Ricardo).
- 18 tray BMC MACs + serials; confirm NIC-mode BMC-MAC choice + dpu_mode field.
- NVLink NVOS-port count (1 vs 2), power-shelf count (6 vs 8).

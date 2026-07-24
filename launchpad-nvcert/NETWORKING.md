# nvcert — Networking Reference

> For the full conceptual design (MetalLB L2 vs BGP rationale, ETP=Local/Cluster trade-offs,
> FNN/EVPN theory, DHCP relay mechanics) see `../launchpad-deploy/NETWORKING.md` — the
> architecture is identical between launchpad and nvcert.

---

## Subnet Layout

| Subnet | Purpose | Gateway | DNS |
|---|---|---|---|
| `172.16.0.0/24` | OOB / switch management | 172.16.0.1 | 172.16.0.1 |
| `172.16.2.0/24` | Host management + NICo VIPs + BMC DHCP pool | 172.16.2.1 | 172.16.0.1 |
| `172.16.3.0/24` | N-S data (tenant underlay) | 172.16.3.1 | — |
| `172.16.5.0/24` | WEKA storage (LACP) | — | — |

---

## 172.16.2.0/24 Address Carve

```
.1          gateway
.11–.13     k8s masters (cp-1, cp-2, cp-3) — static via netplan bond0
.14–.23     k8s workers (cp-4 through cp-13) — static, FILL_ME per node
.30–.39     (reserved / unassigned)
.40–.49     MetalLB VIP pool (see VIP map below)
.50–.250    nico-dhcp managed-host BMC DHCP lease pool
.251–.254   (reserved)
```

### VIP Map (.40–.49)

| VIP | Service | Notes |
|---|---|---|
| `172.16.2.40` | `nico-api` | External pool; ETP=Local (on-subnet from DPU mgmt) |
| `172.16.2.41` | `nico-dhcp` | allocateLoadBalancerNodePorts=false; ETP=Cluster default |
| `172.16.2.42` | `unbound` | .forge DNS resolver |
| `172.16.2.43` | `nico-pxe` | ETP=Local; shared VIP (8080+80) — do NOT flip to Cluster |
| `172.16.2.44` | `nico-ntp` pod-0 | |
| `172.16.2.45` | `nico-ntp` pod-1 | |
| `172.16.2.46` | `nico-ntp` pod-2 | |
| `172.16.2.47` | `nico-dns` pod-0 | |
| `172.16.2.48` | `nico-dns` pod-1 | |
| `172.16.2.49` | `nico-ssh-console-rs` | Cert-auth SSH console (CA fp `SHA256:sPKz…`) |

> nico-pxe (.43) is ETP=**Local** and must STAY Local. The .43 VIP is shared between two
> services (nico-pxe-external :8080 and nico-pxe-external-80 :80, MetalLB allow-shared-ip).
> Flipping ETP on a shared-IP service triggers a MetalLB reallocation that wedges the 8080
> VIP in `<pending>` (recovery = restart metallb-controller).
> See `../launchpad-deploy/NETWORKING.md` for the full analysis.

## MetalLB L2 mode — ARP, not BGP

The site is static-routed: **no BGP advertisement anywhere**. MetalLB runs in L2 mode —
for each VIP, exactly one node's speaker pod **answers ARP** on the mgmt segment, and the
switch learns the VIP's MAC like any host. Two operational consequences:

### 1. strictARP is REQUIRED before NICo (kube-proxy IPVS + MetalLB-L2)

kube-proxy in IPVS mode binds every Service IP to the dummy `kube-ipvs0` interface on
**every** node. Without strict ARP, all nodes answer ARP for the VIPs, fighting MetalLB's
single-owner model → the VIP flaps between nodes / goes intermittently dark.
`install-all.sh` applies this automatically; to check / apply by hand:

```bash
# check — must print: strictARP: true
kubectl -n kube-system get cm kube-proxy -o yaml | grep strictARP

# apply + restart kube-proxy (idempotent)
kubectl -n kube-system get cm kube-proxy -o yaml \
  | sed 's/strictARP: false/strictARP: true/' | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```

### 2. Verifying VIPs (arping) — no BGP convergence to wait for

From a CP node, each VIP should answer ARP within one round-trip:

```bash
for vip in 172.16.2.40 172.16.2.41 172.16.2.42 172.16.2.43 \
           172.16.2.44 172.16.2.45 172.16.2.46 172.16.2.47 \
           172.16.2.48 172.16.2.49; do
  echo "== $vip =="; arping -c 1 -I bond0 "$vip"
done
```

A healthy VIP answers with a reply line — depending on which arping is installed:
`Unicast reply from 172.16.2.40 [<MAC>] 0.3ms` (iputils-arping) or
`60 bytes from <MAC> (172.16.2.40)` (Habets arping; uses `-i` instead of `-I`).

Caveats and the no-reply path:
1. **Test from a node that does not own the VIP** — a node may not put ARP for its own
   address on the wire. If one node sees no reply, cross-check from another node (or a
   host elsewhere on the VLAN-200 segment) before debugging.
2. Confirm the VIP is assigned: `kubectl -n nico-system get svc | grep <VIP>` (a
   `<pending>` EXTERNAL-IP means MetalLB never allocated — check IPAddressPool overlap).
3. Find the owner + speaker health:
   `kubectl -n metallb-system logs -l component=speaker --prefix | grep <VIP>` and
   `kubectl -n metallb-system get pods -o wide`.
4. Stale switch ARP cache after an owner change: restart the owning speaker pod —
   MetalLB sends gratuitous ARP (GARP) on leader election, refreshing the switch.
5. If ALL VIPs are flaky/flapping: strictARP (above) is the first suspect.

---

## Control-Plane Node MACs and Static IPs

| Node | Primary NIC (ens6f0np0) | Bond NIC (ens6f1np1) | Static IP |
|---|---|---|---|
| cp-1 | `6c:83:75:25:64:02` | `6c:83:75:25:64:03` | `172.16.2.11/24` |
| cp-2 | `6c:83:75:25:74:e2` | `6c:83:75:25:74:e3` | `172.16.2.12/24` |
| cp-3 | `6c:83:75:25:6d:14` | `6c:83:75:25:6d:15` | `172.16.2.13/24` |
| cp-4–cp-13 | FILL_ME | FILL_ME | `172.16.2.14–.23` |

---

## DHCP Relay — switch-hosted (the standard setup)

- **Relay:** DHCP relay (ip-helper) configured on the **mgmt switches** (the SN2201s the tray
  BMCs hang off), forwarding to the nico-dhcp VIP `172.16.2.41`.
- **giaddr:** the switch SVI address on the mgmt subnet. On launchpad the relayed requests
  arrive with giaddr `172.16.2.4` / `172.16.2.5`. The exact address doesn't matter:
  nico-dhcp matches the giaddr to `[networks.nvcert-mgmt]` by **subnet membership**
  (`ip <<= prefix`) — any address inside `172.16.2.0/24` selects the right lease pool.
  There is no exact-gateway requirement.
- With the relay on the switch, **nico-dhcp (kea) can schedule on any k8s node** — no
  anti-affinity needed.
- Ask the network team to configure the relay when they set up the mgmt switches
  (launchpad history: started with a node-hosted relay, switch relay took over 2026-06-24).

### Fallback — node-hosted relay (only if the switch relay isn't available yet)

Bring-up can proceed without the networking team: run `isc-dhcp-relay` on cp-1
(`SERVERS=172.16.2.41  INTERFACES=bond0  OPTIONS=-4`, giaddr becomes cp-1's `.11`).
Exact steps: `../launchpad-deploy/DHCP-RELAY.md` §4.

> ⚠️ Fallback-only safety rule: with a node-hosted relay, nico-dhcp (kea) must NOT be
> scheduled on the relay node — a relay forwarding to a VIP backed by a pod on the same
> host goes deaf (caused a real outage on launchpad). Pin kea off the relay node:
> `kubectl -n nico-system patch deploy nico-dhcp` with NodeAffinity
> `NotIn: [<relay-node-name>]`. Lift the pin when the switch relay takes over.

---

## FNN / EVPN

All FNN/EVPN values (datacenter_asn, site_global_vpc_vni, site_fabric_prefixes, vpc_vni,
route-target imports/exports, fnn-asn pool range) are **site-specific** and must be obtained
from the network team (Brian / Jasmeer) before deploy.

They are marked `FILL_ME` in `nico/nico-core.nvcert.yaml` with the launchpad values as shape
reference. See the `[fnn.*]` section and the WARN comment in that file.

---

## Control-Plane BMC Access

Control-plane node BMCs are on the OOB subnet (`172.16.0.0/24`):
- IPs: `172.16.0.28` through `172.16.0.40`
- Credentials: `USERID` / `Buynvidia2026!`

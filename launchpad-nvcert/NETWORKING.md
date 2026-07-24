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

> ETP=Cluster on nico-pxe (.43): do NOT change. The .43 VIP is shared between two services
> (nico-pxe-external port 8080 and nico-pxe-external-80 port 80). Changing ETP on a shared-IP
> service triggers a MetalLB reallocation that wedges the 8080 VIP in `<pending>`.
> See `../launchpad-deploy/NETWORKING.md` for the full analysis.

### Verifying VIPs after Core deploy (arping)

MetalLB L2 mode (no BGP) makes VIPs reachable purely via ARP — the speaker pod on the owning
node responds to ARP requests for each VIP on the mgmt segment. There is no BGP advertisement
or routing-protocol convergence to wait for. Verification is immediate from any CP node:

```bash
# From a CP node — check each VIP has an ARP responder on bond0.
# A reply means MetalLB has the VIP assigned and the speaker is healthy.
for vip in 172.16.2.40 172.16.2.41 172.16.2.42 172.16.2.43 \
           172.16.2.44 172.16.2.45 172.16.2.46 172.16.2.47 \
           172.16.2.48 172.16.2.49; do
  arping -c 1 -I bond0 "$vip" 2>&1 | grep -E "ARPING|bytes from|Sent" | head -2
done
```

A healthy VIP reply looks like:
```
ARPING 172.16.2.40 from 172.16.2.11 bond0
60 bytes from 00:11:22:aa:bb:cc (172.16.2.40): index=0 time=0.334 msec
```

If a VIP returns no reply after ~30s of MetalLB running:
1. Check the speaker pod on the owning node: `kubectl -n metallb-system get pods -o wide | grep speaker`
2. Check which node owns the VIP: `kubectl -n metallb-system logs -l component=speaker --prefix | grep <VIP>`
3. Refresh stale switch ARP caches by triggering a gratuitous ARP from the owning node:
   `kubectl -n metallb-system exec <speaker-pod> -- arping -c 3 -A -I bond0 <VIP>` (if arping is in the image)
   or restart the speaker pod to trigger MetalLB's automatic GARP on leader election.

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

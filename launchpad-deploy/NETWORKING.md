# LaunchPad — Networking Architecture

Authoritative networking design for the GB300 NVL72 **launchpad** site: subnets, VLANs, the
`172.16.2.0/24` address plan, MetalLB/VIPs, DHCP relay, `.forge` DNS, and the NICo siteConfig
mapping. Facts sourced from `stardrive/launchpad-docs/` + coworker/Ricardo + the NICo code.

Two distinct layers, don't conflate them:
- **Site controllers (SC):** 3× Lenovo SR630 V4 (**x86_64**) running the k8s cluster + NICo.
- **Managed hosts:** 18 GB300 trays (**Grace ARM aarch64** host + **BlueField-3** DPU) that NICo ingests.

> **New to networking? Read [§0 Primer](#0-primer--the-concepts-from-the-ground-up) first.** It explains
> IP/MAC, ARP, DHCP + relay, DNS, VIP, MetalLB, and kube-proxy/IPVS in plain language, then shows how they
> combine here. The rest of the doc is the concrete design.

---

## 0. Primer — the concepts from the ground up

Skip if you're comfortable with networking. This explains *what* each piece is, *why* we need it, and
*how it plays together* on this site.

### 0.1 The two addresses every machine has: IP and MAC
- A **MAC address** (e.g. `6c:83:75:25:68:b8`) is the permanent hardware ID burned into a network
  port. It only matters *within a single local network segment* (one switch / one VLAN).
- An **IP address** (e.g. `172.16.2.11`) is a logical address used to route traffic *across* networks.
- **Subnet / CIDR** (e.g. `172.16.2.0/24`) = a block of IPs that share one local segment. "/24" means
  the first 24 bits are the network (`172.16.2.`) and the last 8 bits (`.0`–`.255`) are hosts → 254 usable.
- **Gateway** (e.g. `172.16.2.1`) = the router IP a machine sends to when the destination is *outside*
  its subnet.
- **VLAN** = a way to carve one physical switch into separate virtual networks. Our "VLAN 200" is the
  `172.16.2.0/24` segment; "VLAN 100" is the BMC mgmt segment. Devices on different VLANs can't talk
  except through a router.

### 0.2 ARP — "who has this IP?"
Two machines on the *same* subnet talk by **MAC**, but software addresses things by **IP**. **ARP
(Address Resolution Protocol)** bridges the two: a machine shouts on the local segment *"who has
172.16.2.41? tell me your MAC"*, and the owner replies *"that's me, my MAC is …"*. The asker caches
that and sends the frame to that MAC. **ARP is how an IP gets matched to a physical port on a LAN.**
This matters below because MetalLB makes a VIP reachable precisely *by answering ARP for it*.

### 0.3 DHCP and DHCP relay — "give me an IP automatically"
- **DHCP** = a server hands out IP addresses (plus gateway, DNS, boot info) to machines that ask. A
  machine with no IP **broadcasts** "DHCPDISCOVER" on its local segment; a DHCP server answers.
- Problem: a **broadcast doesn't cross a router/VLAN boundary**. If the DHCP server isn't on the same
  segment as the client, the client's shout never reaches it.
- **DHCP relay** (a.k.a. "ip helper") solves that: a host **on the client's segment** catches the
  broadcast and **unicasts it** to the DHCP server's IP elsewhere, stamping the request with `giaddr`
  (the relay's own IP) so the server knows which segment it came from. The relay does NOT have to be the
  router/gateway — it just has to be on the same broadcast domain as the clients.
- **Why it matters here:** our trays are on VLAN 200, but NICo's DHCP server is a service in the k8s
  cluster (reached at a VIP). NICo *requires* the relay — it ignores non-relayed requests and uses
  `giaddr` to pick the IP pool. **Key finding:** NICo matches `giaddr` to a segment by **subnet
  membership** (`ip <<= prefix`), not by exact gateway — so any address in `172.16.2.0/24` works as the
  relay address. The control-plane nodes' `bond0` (`172.16.2.11-.13`) are on the same VLAN-200 broadcast
  domain as the tray BMCs, so **we self-host the relay on `control-plane-1` instead of the core switch**
  (`isc-dhcp-relay`, bond0 → `172.16.2.41`). No networking-team change needed. Full detail + proof:
  [DHCP-RELAY.md](DHCP-RELAY.md). (Core-switch ip-helper remains the clean long-term option.)

### 0.4 DNS — "what IP is this name?"
**DNS** turns names into IPs (`carbide-api.forge` → `172.16.2.40`). The deployed NICo/DPU agents are
hardcoded to use `*.forge` names, so we run a small DNS server (**unbound**) that knows those names and
forwards everything else to the real resolver. (See §5.)

### 0.5 What a "VIP" is and why services need one
- A normal pod IP changes every time the pod restarts — useless as a stable address.
- A **VIP (Virtual IP)** is a *stable, floating* IP that represents a **service**, not a specific
  machine. Clients always talk to the VIP; whichever node currently "owns" it handles the traffic. If
  that node dies, another node takes the VIP over — the clients never change anything.
- NICo's services (API, DHCP, DNS, PXE, NTP) each get a VIP on `172.16.2.0/24` so the trays and the
  relay always have a fixed address to hit. (See §2 for the VIP map.)

### 0.6 MetalLB — what gives a bare-metal cluster its VIPs
In a cloud, "LoadBalancer" service IPs come from the cloud provider. On bare metal there's no cloud,
so **MetalLB** is the component that hands out VIPs and makes them reachable. Two modes:
- **BGP mode** — MetalLB talks a routing protocol (BGP) to the switches to advertise VIP routes.
  Needs BGP configured on the network. We **don't** use this (the lab is static-routed).
- **L2 mode (we use this)** — MetalLB picks one node to "own" each VIP and that node simply
  **answers ARP** (§0.2) for the VIP on the local segment. To the switch it looks like a normal host.
  Simple, no routing protocol — perfect for a flat static lab.

### 0.7 kube-proxy and IPVS — how the cluster routes its own service traffic
Inside Kubernetes, **kube-proxy** programs each node so that traffic to a service's internal IP gets
load-balanced to the right pods. It can do this with iptables or, in our cluster, with **IPVS** (the
Linux kernel's in-built load balancer — faster at scale). To make IPVS work, kube-proxy binds *all*
the service IPs onto a dummy interface called `kube-ipvs0` on **every** node.

### 0.8 Why MetalLB-L2 + IPVS needs `strictARP: true` (the thing we fixed)
Put §0.2, §0.6-L2, and §0.7 together:
- MetalLB-L2 makes a VIP reachable by having **exactly one** node answer ARP for it.
- But IPVS bound that same VIP onto `kube-ipvs0` on **every** node. By default a Linux node will happily
  answer ARP for *any* IP on *any* of its interfaces — so **every** node would answer ARP for the VIP.
- Result: ARP replies come from multiple nodes, the switch gets confused about who owns the VIP, and the
  VIP **flaps** (traffic bounces between nodes / drops). MetalLB's "one owner" guarantee is broken.
- **`strictARP: true`** tells every node: *only answer ARP for an IP if it's on the real interface that
  received the request* — not for IPs that merely live on the dummy `kube-ipvs0`. Now only MetalLB's
  chosen owner answers, and the VIP is stable. That's why it's a hard requirement for L2 + IPVS, and why
  we patched it in Phase 4a.

### 0.9 How it all comes together (one sentence each)
1. The cluster runs on the 3 site controllers, which sit on the `172.16.2.0/24` segment (VLAN 200).
2. **MetalLB (L2)** gives each NICo service a stable **VIP** in `172.16.2.40–.49` and makes it reachable
   by **answering ARP** for it from one node (kept sane by **strictARP**).
3. A **GB300 tray** powers on with no IP and **broadcasts DHCP**; a **relay on control-plane-1**
   (`isc-dhcp-relay` on bond0 — see [DHCP-RELAY.md](DHCP-RELAY.md)) forwards it to the **nico-dhcp VIP**,
   which leases it an IP from `172.16.2.50–.250` and tells it where to boot.
4. The tray asks **DNS (unbound VIP)** to resolve `carbide-pxe.forge`/`carbide-api.forge` → VIPs, then
   **PXE-boots** from the nico-pxe VIP and checks in with the nico-api VIP.
5. NICo discovers/validates the tray and drives it to **Ready**.

(Detailed, concrete design for each of these follows.)

---

## 1. Subnets / VLANs

| Network | CIDR | VLAN | Gateway | DNS | Role |
|---|---|---|---|---|---|
| OOB mgmt | 172.16.0.0/24 | 100 | 172.16.0.1 | 172.16.0.1 | Switch mgmt (.10–.27); **SC BMCs** (.28–.30) — DHCP from bastion/edge |
| **Managed-host / inband** | **172.16.2.0/24** | **200** | 172.16.2.1 | 172.16.0.1 | **SC OS** + all tray/DPU/NVLink/powershelf BMCs + **NICo service VIPs** + **nico-dhcp lease pool** |
| North-south data | 172.16.3.0/24 | — | 172.16.3.1 | 172.16.0.1 | CX7/DPU data underlay (ens3f*) |
| Storage (WEKA) | 172.16.5.0/24 | — | — | — | CX7 SL1 storage (ens1f*); WEKA .11/.12, NFS .31–40 |
| East-west | (undoc) | — | — | — | CX8 GPU fabric, single VLAN (no IP) |

Notes: SC BMCs (VLAN 100) are served by the bastion's DHCP and are out of NICo's scope. There are
**two /24s for "inband"** (only one in the portal); the second is only needed later if DPU-mode/overlay
is enabled. Everything is **static-routed today** (no BGP in the lab).

---

## 2. `172.16.2.0/24` address plan (the core of the design)

This single /24 (VLAN 200) carries three different things, so the carve keeps them from colliding:

| Range | Use | Assigned by |
|---|---|---|
| `172.16.2.1` | gateway | infra (doc) |
| `172.16.2.11–.13` | **site-controller OS** (cp-1/-2/-3, static netplan, bond0) | us (static) |
| `172.16.2.14–.29` | static headroom (future SC / infra) | reserved |
| **`172.16.2.30–.49`** | **MetalLB VIP pool** (NICo k8s LoadBalancer services) | MetalLB (L2) |
| **`172.16.2.50–.250`** | **nico-dhcp managed-host lease pool** (tray/DPU/NVLink/power BMCs) | NICo (Kea) |
| `172.16.2.251–.254` | reserved | — |

**Why this works:** the NICo admin network (`[networks.admin]`, prefix `172.16.2.0/24`) is configured
with **`reserve_first = 50`**, so NICo never allocates an address ≤ `.50` to a managed host. That
fences off the SC statics (.11–.13) and the MetalLB VIPs (.30–.49) from the DHCP lease pool (.50–.250).
~96 managed endpoints (18 trays × 4 + 9 NVLink×~2 + 6 power) fit comfortably in `.50–.250`.

### NICo service VIP map (MetalLB, from .30–.49)
| Service | VIP | Pool | `.forge` name |
|---|---|---|---|
| nico-api | 172.16.2.40 | external | carbide-api.forge |
| nico-dhcp | 172.16.2.41 | internal | — (relay target) |
| unbound | 172.16.2.42 | internal | unbound.forge (+ serves the zone) |
| nico-pxe | 172.16.2.43 | internal | carbide-pxe.forge / carbide-static-pxe.forge |
| nico-ntp 0/1/2 | 172.16.2.44/.45/.46 | internal | carbide-ntp.forge |
| nico-dns 0/1 | 172.16.2.47/.48 | internal | (authoritative site DNS) |
| nico-ssh-console-rs | 172.16.2.49 | internal | — (cert-auth console — see [SSH-CONSOLE.md](SSH-CONSOLE.md)) |

---

## 3. MetalLB — L2 mode + strictARP

The lab is **static-routed (no BGP)**, so MetalLB runs in **L2 (ARP) mode** (`L2Advertisement`). The
SC nodes' `bond0` is on `172.16.2.0/24`, so MetalLB answers ARP for the VIPs directly on that segment
— no routing/BGP needed.

**Why `strictARP: true` is required:** with `kube-proxy` in **IPVS** mode (our cluster), every node
binds all Service cluster-IPs to the dummy `kube-ipvs0` interface. Without strict ARP, a node will
answer ARP requests for IPs that live on `kube-ipvs0` even when it shouldn't — which **fights MetalLB's
L2 leader election** for the VIP and causes the VIP to flap / answer from the wrong node. Setting
`ipvs.strictARP: true` makes nodes reply to ARP **only** for addresses actually configured on a real
interface, so exactly one MetalLB speaker owns each VIP's ARP. (MetalLB documents this as a hard
requirement for L2 + IPVS.) Applied via:
```bash
kubectl -n kube-system get configmap kube-proxy -o yaml \
  | sed 's/strictARP: false/strictARP: true/' | kubectl apply -f -
kubectl -n kube-system rollout restart daemonset kube-proxy
```
Status: **applied** (kube-proxy configmap patched, daemonset restarted).

---

## 4. DHCP for managed hosts — relay is MANDATORY

NICo's DHCP (Kea + nico hook) **rejects any packet whose `giaddr` is 0.0.0.0** (non-relayed) and
**selects the network segment by matching the relay's `giaddr` to a segment by subnet membership**
(`ip <<= prefix`), so any address in `172.16.2.0/24` works. So a flat broadcast from a tray will never
get an answer — a **DHCP relay** must forward tray DHCP to the nico-dhcp VIP. Here that relay is a
self-hosted `isc-dhcp-relay` on cp-1 (giaddr `172.16.2.11`).

```
GB300 tray BMC/DPU (172.16.2.0/24, VLAN 200)
      │  DHCPDISCOVER (broadcast)
      ▼
Self-hosted isc-dhcp-relay on cp-1 (bond0)  ── unicast, giaddr 172.16.2.11 ──►  nico-dhcp VIP 172.16.2.41
      ▲                                                                              │
      └────────────── DHCPOFFER (IP from .50–.250 + next-server/bootfile/DNS/NTP) ◄──┘
```
- We self-host the relay as **`isc-dhcp-relay` on `launchpad-control-plane-1`** (`cp-1`, on bond0, same
  VLAN-200 broadcast domain as the tray BMCs). It sets `giaddr = 172.16.2.11` (cp-1's bond0 IP), which
  is in `172.16.2.0/24` → NICo matches the mgmt underlay segment and leases from `.50–.250`. It forwards
  to the nico-dhcp VIP `172.16.2.41`. Full detail: [DHCP-RELAY.md](DHCP-RELAY.md).

---

## 5. `.forge` DNS (unbound)

Deployed DPU/host agents are hardcoded to resolve `*.forge` names. The bundled **unbound** (VIP
`172.16.2.42`) is authoritative for the `.forge` zone and forwards everything else upstream. DHCP
option 6 hands clients the unbound VIP. Mappings:

| Name | → VIP |
|---|---|
| carbide-api.forge / nico-api.forge | 172.16.2.40 |
| carbide-pxe.forge / nico-pxe.forge / carbide-static-pxe.forge | 172.16.2.43 |
| carbide-ntp.forge / nico-ntp.forge | 172.16.2.44/.45/.46 |
| unbound.forge | 172.16.2.42 |

Upstream forwarder: the site resolver (assume `172.16.0.1`; confirm).

---

## 6. NICo siteConfig ↔ physical mapping

| Physical | siteConfig | Notes |
|---|---|---|
| 172.16.2.0/24 (VLAN 200) | `[networks.launchpad-mgmt]` type=underlay prefix=172.16.2.0/24 gw=172.16.2.1 reserve_first=50 | managed-host DHCP + discovery (trays DHCP here) |
| (placeholder) | `[networks.admin]` prefix=172.16.4.0/25 gw=172.16.4.1 | placeholder — admin never allocates in NIC mode |
| 172.16.3.0/24 | `[networks.<ns>] type=underlay` | north-south data |
| — | `deny_prefixes = []` | emptied on launchpad; do NOT deny mgmt underlay 172.16.2.0/24 (holds the VIPs) |
| tenant fabric / EVPN | `site_fabric_prefixes=172.16.4.128/25`, `datacenter_asn=32325`, `[pools.fnn-asn]`, `site_global_vpc_vni=245002` | siteConfig now carries a full FNN/EVPN config |
| nico-dhcp VIP | `dhcp_servers = ["172.16.2.41"]` | |

The siteConfig now carries a full **FNN/EVPN** config — `datacenter_asn=32325`,
`site_fabric_prefixes=172.16.4.128/25`, `[pools.fnn-asn]`, `site_global_vpc_vni=245002` — so the
EVPN/DPU-mode route-target machinery is now **present** in siteConfig (no longer a bare NIC-mode/no-VXLAN
placeholder). Whether DPU offload is actively exercised still depends on per-host dpu-mode + upstream
BGP peering.

---

## 7. End-to-end packet/identity flow (managed-host ingestion)
1. Tray powers on → BMC/DPU broadcasts DHCP on VLAN 200.
2. cp-1 `isc-dhcp-relay` → nico-dhcp VIP (`.41`); NICo matches giaddr `172.16.2.11` → launchpad-mgmt underlay → leases `.50–.250` + next-server (nico-pxe `.43`) + DNS (unbound `.42`) + NTP (`.44–.46`).
3. iPXE (**aarch64**) fetches scout/carbide + BFB from nico-pxe.
4. site-explorer probes the tray BMC via Redfish (creds from Vault) → creates the managed host (must be in `expected_machines`).
5. State machine `HostInit → BomValidating → Ready` (DPU-discovery skipped in NIC mode).

---

## 8. Status / open networking items
- ✅ SC statics (.11–.13), MetalLB carve (.30–.49), strictARP applied.
- ✅ **DHCP relay → 172.16.2.41**: self-hosted `isc-dhcp-relay` on cp-1 (giaddr `172.16.2.11`). See [DHCP-RELAY.md](DHCP-RELAY.md).
- ⬜ Confirm unbound upstream resolver IP.
- ⬜ 2nd inband /24 CIDR (only for future DPU-mode/overlay + lo-ip).
- ⬜ Verify NVLink NVOS-port count (1 vs 2) + power-shelf count (6 vs 8) for DHCP-pool sizing.

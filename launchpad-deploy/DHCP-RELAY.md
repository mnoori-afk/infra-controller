# LaunchPad DHCP Relay — what it is, why we self-host it, and how it runs

_Written 2026-06-14. This documents the decision to run the DHCP relay **on a control-plane node**
instead of asking the networking team to configure it on the core switch, the evidence behind that
decision, the exact commands used, and how to operate it._

Related: [NETWORKING.md](NETWORKING.md) · [STATUS.md](STATUS.md) · memory `project_nico_pxe_ingestion_gotchas`.

---

## 1. Plain-English: why a relay is needed at all

For a GB300 tray to boot over the network and be ingested, its **BMC** (the little always-on
management computer on the tray) must first get an IP address. It gets one by **broadcasting** a
DHCP request ("anyone, please give me an IP"). 

NICo runs a DHCP server (`nico-dhcp`), but it deliberately **ignores broadcast requests that arrive
directly** — it only answers requests that have been **relayed** (forwarded by a helper that stamps
the packet with a "this came from network X" address, the `giaddr` field). This is by design
(`crates/dhcp-server/src/packet_handler.rs`: a packet with `giaddr == 0.0.0.0` is rejected as
`NonRelayedPacket`).

So we need a **DHCP relay**: a process sitting on the trays' network that catches their broadcasts,
stamps each with an address, and forwards it (unicast) to NICo's DHCP service. NICo then picks the
right network, allocates an IP from the pool, and replies back through the relay to the tray.

```
 Tray BMC  --broadcast "give me an IP"-->  [ DHCP RELAY ]  --unicast, giaddr stamped-->  nico-dhcp (172.16.2.41)
 Tray BMC  <----------------- IP + boot info (DHCPACK) ------------------------------     nico-dhcp
```

The conventional place for a relay is the **core switch** (it already has a leg on every VLAN). But
that needs the networking team. We found we can run it ourselves on a control-plane node — below is
why that's valid and how.

---

## 2. The investigation — how we knew a node-hosted relay would work

Two questions had to both be "yes". We answered each with hard evidence, not assumption.

### Q1 (code): Does NICo require the relay's `giaddr` to be *exactly* the gateway `172.16.2.1`?

If yes, only the core switch (which owns `172.16.2.1`) could relay. If NICo just needs the `giaddr`
to be *somewhere inside* `172.16.2.0/24`, then a node using its own address `172.16.2.11` works.

**Answer: subnet membership, NOT exact gateway.** The segment selector in
`crates/api-db/src/network_segment.rs` (`for_relay_all`) is:

```sql
WHERE ip <<= network_prefixes.prefix      -- postgres inet "is contained within or equal"
```

`<<=` means "is the relay IP inside this segment's prefix?" — so **any** address in `172.16.2.0/24`
(including a control-plane node's `172.16.2.11`) selects `[networks.admin]`. The only hard rule
(`packet_handler.rs`) is `giaddr != 0` (must be relayed at all).

> This corrected an earlier wrong assumption (mine, and a common one) that "giaddr must equal the
> gateway." It does not. That single fact is what makes self-hosting possible.

### Q2 (topology): Are the control-plane nodes on the same L2 network as the tray BMCs?

A relay only works if it can physically *hear* the trays' broadcasts (same Ethernet broadcast
domain / VLAN). From the launchpad docs (`control-plane.md`, `compute-trays.md`, `access-and-networks.md`):

| Thing | Switch | Subnet | Gateway |
|---|---|---|---|
| Tray BMCs | `gb300-01-sn2201dc-mgmt-sw-01/02` | `172.16.2.x/24` | `172.16.2.1` |
| Control-plane node inband (`bond0` = `ens6f0np0`+`ens6f1np1`) | `gb300-01-sn2201-mg-01/02` | `172.16.2.x/24` | `172.16.2.1` |

Different physical switches, but the **same `/24` and the same single gateway `172.16.2.1`**. You
cannot have one subnet + one gateway IP spread across two *separate* L3 segments — so VLAN 200 is one
broadcast domain trunked across both switch sets. ⇒ the nodes' `bond0` can hear the tray BMC
broadcasts. (The **bastion** is on `172.16.0.x` / OOB, so it is NOT a valid relay host — skipped.)

### The empirical confirmation (the decider)

Theory is nice; we proved it by listening on the node's `bond0` for the trays' DHCP broadcasts:

```bash
tsh ssh launchpad-control-plane-1 "sudo timeout 45 tcpdump -ni bond0 -e -t 'udp and (port 67 or port 68)'"
```

Result: **all 18 tray BMC MACs** (`18:3d:2d:9b:b3:f2`, `…:b4:1c`, `…:b3:e8`, … — matching the 18 in
`nico/expected_machines.launchpad.json`) plus several DPU BMC MACs (`e0:9d:73:*`) were seen
broadcasting `0.0.0.0.68 > 255.255.255.255.67 BOOTP/DHCP Request`. The trays were powered, asking for
IPs, and **their broadcasts reach the control-plane node**. Both questions answered "yes" → proceed.

---

## 3. The decisions we took (and why)

| Decision | Choice | Why |
|---|---|---|
| **Relay location** | **Control-plane node (`launchpad-control-plane-1`)**, not the core switch | Removes the networking-team dependency for bring-up; the node is L2-adjacent to the trays and NICo matches its `.11` giaddr by subnet. Core-switch ip-helper remains the cleaner *long-term* home. |
| **Not the bastion** | Excluded | Bastion is on OOB `172.16.0.x`, not on VLAN 200 / `172.16.2.0/24` — it can't hear tray broadcasts and its IP isn't in the admin prefix. |
| **How many nodes** | **One (cp-1)** | One relay is plenty to ingest 18 trays. Running on all 3 makes every request reach NICo 3× (from giaddr `.11/.12/.13`) → duplicate DHCP processing + extra cache entries (the dhcp cache key includes the relay address). If cp-1 reboots mid-ingest, restart the service or stand it up on cp-2 in seconds. |
| **Relay software** | `isc-dhcp-relay` (Ubuntu pkg, `dhcrelay`) as a **systemd service** | The node has apt egress (verified), so the OS package is the simplest reboot-persistent option. No container image / registry-pull concerns. (Fallback if no apt egress: a hostNetwork pod running `dhcrelay`.) |
| **Forward target** | `172.16.2.41` (the `nico-dhcp` MetalLB VIP) | That's NICo's DHCP service address (set in `nico-core.launchpad.yaml` + `metallb-config.launchpad.yaml`). |
| **Listen interface** | `bond0` | The node's inband VLAN-200 interface (`172.16.2.11/24`) — the one that hears the trays. |
| **IPv6 relay** | disabled | We only DHCP over IPv4 here; leaving `isc-dhcp-relay6` enabled just produces a failing/idle unit. |

---

## 4. Exactly what was run to get "Relay is running"

All on `launchpad-control-plane-1` via `tsh ssh launchpad-control-plane-1` (no `user@` — Teleport maps
the principal; `sudo` needs no password).

**a. Confirm the node can install it + has the right interface (investigation):**
```bash
which dhcrelay dnsmasq                       # -> neither installed
apt-cache policy isc-dhcp-relay              # -> Candidate: 4.4.3-P1-4ubuntu2 (installable)
curl -sS -o /dev/null -w '%{http_code}' http://archive.ubuntu.com/   # -> 200 (apt egress works)
ip -br addr show bond0                        # -> bond0  UP  172.16.2.11/24
```

**b. Install:**
```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq isc-dhcp-relay
```

**c. Configure** (`/etc/default/isc-dhcp-relay`, read by the packaged systemd unit):
```ini
SERVERS="172.16.2.41"      # forward to nico-dhcp VIP
INTERFACES="bond0"         # listen on the VLAN-200 inband interface
OPTIONS="-4"               # IPv4 only
```

**d. Start it, and disable the unused IPv6 relay:**
```bash
sudo systemctl disable --now isc-dhcp-relay6.service
sudo systemctl restart isc-dhcp-relay.service
```

**What this does:** `systemd` launches `/usr/sbin/dhcrelay -d -4 -i bond0 172.16.2.41`. `dhcrelay`
opens a packet socket on `bond0`, catches every DHCP broadcast it hears there, rewrites it as a
unicast packet with `giaddr = 172.16.2.11` (bond0's address), and forwards it to `172.16.2.41:67`.
Replies from NICo come back to the relay, which forwards them to the tray. `-d` keeps it in the
foreground so its logs go to `journald`. The service is enabled, so it restarts on boot.

> Benign log line: `Discarding packet received on ens6f0np0/ens6f1np1 ... no IPv4 address`. Those are
> bond0's two physical member NICs (they have no IP of their own); the same frames also arrive on
> `bond0` (which has `.11`) and are relayed correctly. Cosmetic, not an error.

---

## 5. How we confirmed it actually works (end-to-end proof)

**Service is up:**
```bash
tsh ssh launchpad-control-plane-1 "systemctl is-active isc-dhcp-relay; pgrep -af dhcrelay"
# active
# /usr/sbin/dhcrelay -d -4 -i bond0 172.16.2.41
```

**NICo is receiving the relayed requests and answering** — from `nico-dhcp` pod logs
(`kubectl -n nico-system logs -l app.kubernetes.io/name=nico-dhcp`):
```
LOG_CARBIDE_GENERIC ... discovery - returning ... response for (FA:1F:E5:4D:D6:93, 172.16.2.11, ...)   <- relay_address = our node's .11
DHCP4_LEASE_ALLOC ... lease 172.16.2.107 has been allocated for 3600 seconds                            <- NICo handed out an IP
LOG_CARBIDE_PKT4_SEND ... msg_type=DHCPACK ... remote_address=172.16.2.11:67                            <- reply sent back via the relay
   type=003 (router):     172.16.2.1
   type=006 (dns):        172.16.2.42     (unbound, serves .forge)
   type=042 (ntp):        172.16.2.44/.45/.46
```

The `relay_address=172.16.2.11` line is the live confirmation of the §2-Q1 finding: NICo accepted our
node's address as the relay and matched it into `[networks.admin]` by subnet membership. Leases are
being handed out of the `.50–.250` pool (observed `.107`, `.120–.123`, …).

**Conclusion:** the DHCP path (tray → relay on cp-1 → `nico-dhcp` → reply) is fully working. Task #7
("DHCP relay") is complete **without any core-switch / networking-team change.**

---

## 6. Operating it

```bash
# status / logs
tsh ssh launchpad-control-plane-1 "systemctl status isc-dhcp-relay --no-pager; journalctl -u isc-dhcp-relay -n 50 --no-pager"

# restart
tsh ssh launchpad-control-plane-1 "sudo systemctl restart isc-dhcp-relay"

# move to another node (e.g. if cp-1 is drained): run the §4 install+config steps on cp-2,
#   the giaddr becomes 172.16.2.12 — still inside 172.16.2.0/24, so NICo matches it the same way.

# remove entirely (revert)
tsh ssh launchpad-control-plane-1 "sudo systemctl disable --now isc-dhcp-relay; sudo apt-get remove -y isc-dhcp-relay"
```

**When the core switch eventually gets its own ip-helper** (the clean long-term setup), stop this
service so the trays aren't relayed twice.

---

## 7. What's next (this relay unblocks ingestion)

The relay only gets the trays *addresses*. To actually **ingest** them, NICo's site-explorer must
know which BMCs to probe over Redfish — that's the `expected_machines` list:

```bash
export KUBECONFIG=/Users/mnoori/go/src/stardrive/sites/launchpad/kubeconfig
POD=$(kubectl -n nico-system get pod -l app.kubernetes.io/name=admincli -o jsonpath='{.items[0].metadata.name}')
kubectl -n nico-system cp launchpad-bringup/nico/expected_machines.launchpad.json $POD:/tmp/em.json
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli expected-machine replace-all --filename /tmp/em.json
# then watch:  ... expected-machine show   and   ... machine list
```

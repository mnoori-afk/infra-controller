# LaunchPad Site-Controller Bring-Up — Reproducible Runbook

End-to-end record of how the GB300 NVL72 **LaunchPad** site controllers were brought up:
every decision (with rationale), the resulting state, and the exact commands to reproduce.
Authoritative facts sourced from `stardrive/launchpad-docs/` (read-only) + coworker/Ricardo notes.

- **Started:** 2026-06-12. **Phases 1–3b complete** (static IPs, Teleport SSH, k8s, kube-agent): 2026-06-13. **Phase 4 (NICo) next.**
- **Repo home:** `infra-controller-core/launchpad-bringup/` (this dir).
- Companion docs: `PLAN.md`, `STATUS.md`, `PHASE1-static-ip.md`, `PHASE2-teleport.md`, `PHASE3-deployctl.md`.

---

## 1. Site facts

- **Platform:** NVIDIA GB300 NVL72, prefix `gb300-01`. 18 compute trays (BlueField DPU each, **offload disabled**),
  9 NVLink switches, 6 power shelves (doc count — coworker thinks possibly 8; NVLink may have 2 NVOS ports — verify).
- **Bastion:** `ssh -i ~/.ssh/id_rsa nvidia@72.25.67.5` (key auth). Reaches 172.16.0.x (BMCs/switches) + 172.16.2.x.
- **Credentials:** control-plane BMC `USERID / Buynvidia2026!`; OS `nvidia / NVIDIALaunchPad!`; switches `cumulus / Buynvidia2026!`;
  tray BMC `admin`, NVLink BMC `root`, NVLink mgmt `admin` (all `Buynvidia2026!`); power shelves `root / 0penBmc`.

### Networks (doc-authoritative)
| Net | CIDR | GW | DNS | Role |
|---|---|---|---|---|
| OOB mgmt | 172.16.0.0/24 | .0.1 | .0.1 | switches .10–.27, control-plane **BMCs** .28–.40 (VLAN 100, bastion DHCP) |
| Managed-host/inband | 172.16.2.0/24 | .2.1 | .0.1 | **VLAN 200** — SC OS + all tray/DPU/NVLink/powershelf BMCs |
| North-south data | 172.16.3.0/24 | .3.1 | .0.1 | CX7 SL3 (ens3f*) — underlay |
| Storage (WEKA) | 172.16.5.0/24 | — | — | CX7 SL1 (ens1f*) |
| East-west | (undoc) | — | — | CX8, single VLAN |

Coworker notes: SC BMCs = VLAN 100 (bastion DHCP); other BMCs = VLAN 200 (relay on core switch);
there are **2× /24 inband** (only one in portal), static routes/forwarding today; DPUs can flip to
DPU-mode but then need BGP peering with the core switch.

---

## 2. The 3 chosen site controllers

| Node (hostname) | OS IP (bond0) | BMC IP | BMC switch | TPM EK public hash |
|---|---|---|---|---|
| launchpad-control-plane-1 | 172.16.2.11/24 | 172.16.0.28 | sn2201-mg-01 | 0257b9155233ae69a755f19efd321c81e91de5b45acd1d9bfdc80959cca0c672 |
| launchpad-control-plane-2 | 172.16.2.12/24 | 172.16.0.29 | sn2201-mg-02 | c58849c98842222e2969c736c90abd54c7d687e1e841cc41a2f6cfeb4f4e6be5 |
| launchpad-control-plane-3 | 172.16.2.13/24 | 172.16.0.30 | sn2201-mg-01 | 1e75bed1cff06ff051e6750478cc4fcedf47d21a65c50a975228dca10307d1c5 |

Hardware: Lenovo ThinkSystem SR630 V4, Ubuntu 24.04.3 (kernel 6.8), TPM 2.0 present (`/dev/tpmrm0`).
Common: GW `172.16.2.1`, DNS `172.16.0.1`, `bond0` active-backup over `ens6f0np0`+`ens6f1np1`.

---

## 3. Decisions (with rationale)

1. **No ISO / no stardrive Forge install.** OS already on the nodes → we configure the running OS directly.
2. **SC OS IP on 172.16.2.0/24 (VLAN 200), not 172.16.3.x.** Docs put the 1G OCP mgmt NICs (ens6f*) on
   172.16.2.x; that's the bastion-reachable management path. 172.16.3.x is the CX7 *data* underlay (ens3f*),
   not an access path.
3. **Static host octets `.11/.12/.13`.** Docs reserve none; chose a low static block below the future
   `nico-dhcp` pool. `/24` carve: `.1` gw · `.11–.13` SC · `.14–.29` static hdrm · `.30–.250` nico-dhcp · `.251–.254` rsvd.
   (The earlier runtime `.200` hack was arbitrary/throwaway; expect a possible renumber if SC moves to a
   dedicated subnet from the 2nd inband /24 — do it before k8s if so.)
4. **bond0 = active-backup (not LACP).** The two ens6 ports land on different switches (mg-01/mg-02); LACP
   needs a single MLAG peer. Mirrors the stock subiquity config.
5. **Apply via temp-IP + SSH paste.** Nodes had no DHCP; set the SAME final IP as a runtime addr in the KVM
   (2 short lines), then SSH from the bastion to paste the persistent netplan (no editor/long typing in KVM).
6. **Hostnames `launchpad-control-plane-N`.** Enforces the 3-way alignment (OS hostname == Teleport nodename
   == k8s node name == deployctl node name).
7. **Teleport: TPM join on nv-stg.** Matches stardrive's real flow (`--join-method=tpm`); labels
   `environment=non-prod, resource-group=forge, site=launchpad`; token `rg-forge-launchpad-nodes-tpm`.
8. **k8s substrate = NKE Tier0 (not kubespray).** The reference staging site `dev8` uses NKE Tier0; we match it.
   Substrate-only (bare K8s) since NICo deploys on top via helm-prereqs, not the DSX ArgoCD app stack.

---

## 4. Reproduce — Phase 1: persistent static IPs  ✅ DONE

Per node, via BMC console then bastion SSH (cp-1 / `.11` shown):

```bash
# Console access (KVM preferred; SOL was flaky). Local-forward the BMC web UI through the bastion:
ssh -i ~/.ssh/id_rsa -L 8028:172.16.0.28:443 -N nvidia@72.25.67.5     # .29->8029, .30->8030
# browse https://localhost:8028  (USERID/Buynvidia2026!) -> Remote Console -> HTML5 KVM
# BMC SSH key-offer fix if needed:  ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password -o IdentitiesOnly=yes USERID@172.16.0.28
# XCC SOL cmd is `console start` (exit Esc then "("); stuck session -> `resetsp` (restarts BMC only, NOT host).

# In the KVM (login nvidia/NVIDIALaunchPad!), 2-line temp IP (use the FINAL octet so SSH won't drop later):
sudo ip addr add 172.16.2.11/24 dev bond0
sudo ip route add default via 172.16.2.1

# From the bastion, SSH in and write the persistent config:
ssh nvidia@172.16.2.11
sudo cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak
sudo tee /etc/netplan/00-installer-config.yaml >/dev/null <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens6:
      dhcp4: false
      match:
        name: ens6*
  bonds:
    bond0:
      dhcp4: false
      interfaces: [ens6]
      addresses: [172.16.2.11/24]
      routes:
        - to: default
          via: 172.16.2.1
      nameservers:
        addresses: [172.16.0.1]
      parameters:
        mode: active-backup
        mii-monitor-interval: 100
        transmit-hash-policy: layer3+4
EOF
sudo chmod 600 /etc/netplan/00-installer-config.yaml
sudo netplan generate && sudo netplan apply
sudo hostnamectl set-hostname launchpad-control-plane-1
```
Ready-made per-node files: `netplan/cp-{1,2,3}_00-installer-config.yaml`.

**Verified (reboot-persistent) from the bastion:**
```bash
for ip in 11 12 13; do ssh nvidia@172.16.2.$ip 'hostname; ip -br a show bond0; ip route | grep default'; done
# all 3: correct hostname, 172.16.2.1{1,2,3}/24 UP, default via 172.16.2.1 — survives reboot.
```

---

## 5. Reproduce — Phase 2: Teleport (TPM join, nv-stg)  ✅ DONE

Two-sided TPM handshake. Node side run as root on each node:
```bash
ls -l /dev/tpmrm0                                                    # TPM present
curl -fsS https://nv-stg-dgxc.teleport.sh/webapi/ping && echo OK     # proxy reachable (server v18.8.3)
curl -fsSL "https://nv-stg-dgxc.teleport.sh:443/scripts/install.sh" -o /tmp/ti.sh && sudo bash /tmp/ti.sh
sudo tbot tpm identify                                               # capture EK Public Hash
sudo teleport node configure --output=/etc/teleport.yaml --join-method=tpm \
  --token=rg-forge-launchpad-nodes-tpm --proxy=nv-stg-dgxc.teleport.sh:443 \
  --labels="environment=non-prod,resource-group=forge,site=launchpad"
sudo systemctl enable --now teleport
sudo teleport-update enable --proxy nv-stg-dgxc.teleport.sh:443 || true
```
(Script form: `teleport/install_teleport.sh`.)

Server side (admin, from a host with tsh/tctl) — register the EK hashes:
```bash
tsh login --proxy=nv-stg-dgxc.teleport.sh
tctl create -f teleport/launchpad-token.yaml      # rg-forge-launchpad-nodes-tpm + the 3 EK hashes
```
**Verified:** `tsh ls | grep launchpad` shows all 3 as `Tunnel` with the 3 labels. Access:
`tsh ssh launchpad-control-plane-1`. (This is also how the laptop reaches the nodes now.)

Files: `teleport/install_teleport.sh` (node), `teleport/launchpad-token.yaml` (server).

---

## 6. Phase 3: Kubernetes (kubespray via stardrive)  ✅ DONE (2026-06-13)

Substrate = **kubespray**, NOT NKE Tier0 (NKE `node_setup` netplan-rekey + OVS assume a single NIC,
CDEVS-2906; our mgmt is a bond). Provisioned with stardrive's older kubespray wrapper (it already had
Teleport access):
```bash
cd /Users/mnoori/go/src/stardrive
./stardrive prod provision --teleport-proxy stg --site launchpad \
  --managed-host-config-file managed_host_config/launchpad.yaml --yes
```
Result: 3-node control plane (also workers), **k8s v1.30.4**, **CNI Calico**, kube-proxy **ipvs**.
kubeconfig at `stardrive/sites/launchpad/kubeconfig` (context `launchpad`); all nodes Ready.
(`managed_host_config/launchpad.yaml` = the hosts/jumphost file; reached via the bastion ProxyJump.)
NOTE: the deployctl path (`dsx-ansible-collections` branch `launchpad`, kubespray substrate) is the
maintained equivalent and is committed for parity, but the stardrive wrapper is what we actually ran.

## 6b. Phase 3b: Teleport kube-agent (cluster onboarding)  ✅ DONE (2026-06-13)

Cluster registered in nv-stg as **`rg-forge-launchpad`**; `tsh kube login rg-forge-launchpad` works.
```bash
# server side — register the kube join token (cluster JWKS) on nv-stg:
tsh login --proxy=nv-stg-dgxc.teleport.sh
export KUBECONFIG=/Users/mnoori/go/src/stardrive/sites/launchpad/kubeconfig
cd /Users/mnoori/go/src/stardrive/forged
./components/teleport/joincluster.sh rg-forge-launchpad "$(kubectl config current-context)"
# client side — deploy the agent (values: teleport/kube-agent-values.yaml):
helm upgrade --install teleport-kube-agent teleport/teleport-kube-agent --version 18.7.6 \
  -n teleport --create-namespace -f launchpad-bringup/teleport/kube-agent-values.yaml
```
**GOTCHA (cost an hour):** the agent values MUST set `teleportClusterName: nv-stg-dgxc.teleport.sh`
— it sets the projected ServiceAccount-token **audience**; without it the join fails with
`invalid audience claim (aud)`. Also `adminClusterRoleBinding.name: access-forge-dgxc-prod-admin`
maps your tsh kube group to cluster-admin. If a stale pod keeps the old (broken) spec,
`kubectl -n teleport delete pod teleport-kube-agent-0` to force the new projection.

---

## 7. Current state snapshot (2026-06-13)
- 3 site controllers: static IPs persistent; reachable from bastion AND Teleport (SSH).
- Teleport SSH: all 3 enrolled (TPM), token `rg-forge-launchpad-nodes-tpm`.
- **k8s: UP** — v1.30.4, Calico, 3 Ready nodes; kubeconfig `stardrive/sites/launchpad/kubeconfig`.
- **k8s in Teleport: UP** — `rg-forge-launchpad` (`tsh kube login rg-forge-launchpad`).
- NICo: not yet deployed (Phase 4 next).

## 8. Next — Phase 4: NICo (tasks #4–#6)
- **4a Pre-NICo prep:** kube-proxy `strictARP=true` (ipvs+MetalLB-L2) + restart; confirm nodes
  untainted/schedulable (≥3); confirm sysctls `bridge-nf-call-iptables=1`, `ip_forward=1`.
- **4b NICo install:** `helm-prereqs/setup.sh` — MetalLB pool on `172.16.2.0/24` (.30–.250, L2),
  siteConfig (admin=172.16.2.0/24, underlay=172.16.3.0/24, pools, deny_prefixes), per-service VIPs,
  unbound `.forge` zone, `NICO_IMAGE_REGISTRY`/tags + pull secret. Run `preflight.sh` first.
- **4c DHCP relay (✅ DONE 2026-06-14):** SELF-HOSTED on control-plane-1 (`isc-dhcp-relay`, bond0 →
  nico-dhcp VIP 172.16.2.41) — NOT the core switch. Valid because NICo matches `giaddr`→segment by subnet
  membership (`ip <<= prefix`) and the cp nodes share VLAN-200 with the trays. Proven via tcpdump (18 tray
  BMCs broadcasting) + nico-dhcp logs (relay_address=.11, LEASE_ALLOC, DHCPACK). Full detail: DHCP-RELAY.md.
- **4d Tray ingestion (next):** `expected-machine replace-all` with `nico/expected_machines.launchpad.json`
  (18 trays); watch site-explorer discover BMCs via Redfish → PXE → Ready. DPU offload off (NicMode).

## 9. Open items / TODO
- Verify hardware counts: NVLink NVOS ports (1 vs 2/switch), power shelves (6 vs 8) — DHCP pool sizing.
- 2nd inband /24 CIDR — only needed for later NICo DPU-mode loopbacks/overlay.
- Get Ricardo's networking outline before he's out next week.
- k8s v1.30.4 is fine for NICo; bump only via a matching kubespray version.

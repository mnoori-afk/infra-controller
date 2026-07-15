# Compute Trays

Compute trays include tray BMC, DPU BMC, DPU host OOB, host OOB, storage, and east-west fabric links. Rows with no IP address are cabling references.

> **Note**
>
> Compute tray BMC, DPU BMC, DPU host OOB, and host OOB interfaces are on the 172.16.2.x management network and are reached from the control-plane nodes. Use storage interfaces for WEKA access and east-west interfaces for inter-compute tray communication.

> **Note**
>
> East-west interfaces are configured on a single VLAN. During operating system configuration you may need to account for ARP flux behavior; see the NVIDIA DGX OS user guide for mitigation guidance: [DGX OS 7 User Guide](https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf).

## Compute Tray BMC Browser Access

After DHCP is configured on a control-plane node, the compute tray BMCs should receive addresses on the 172.16.2.x management network. DHCP reservations are recommended so each tray keeps a stable BMC address, but the tunnel command can use whatever addresses your DHCP setup assigns.

Run SSH port forwarding from the bastion desktop through a control-plane node that can reach the compute tray BMC network. In this example, `username@172.16.2.10` is the control-plane node, and `172.16.2.11-28` are example compute tray BMC addresses. Update the target IPs to match your DHCP leases or reservations.

```bash
ssh -fN \
  -L 8411:172.16.2.11:443 \
  -L 8412:172.16.2.12:443 \
  -L 8413:172.16.2.13:443 \
  -L 8414:172.16.2.14:443 \
  -L 8415:172.16.2.15:443 \
  -L 8416:172.16.2.16:443 \
  -L 8417:172.16.2.17:443 \
  -L 8418:172.16.2.18:443 \
  -L 8419:172.16.2.19:443 \
  -L 8420:172.16.2.20:443 \
  -L 8421:172.16.2.21:443 \
  -L 8422:172.16.2.22:443 \
  -L 8423:172.16.2.23:443 \
  -L 8424:172.16.2.24:443 \
  -L 8425:172.16.2.25:443 \
  -L 8426:172.16.2.26:443 \
  -L 8427:172.16.2.27:443 \
  -L 8428:172.16.2.28:443 \
  username@172.16.2.10
```

After you enter the control-plane node password, SSH starts the tunnels in the background. Open the BMC web interfaces from a browser on the bastion desktop using the local forwarded ports.

| Bastion Browser URL | Forwarded BMC Target |
|---|---|
| `https://localhost:8411` | `172.16.2.11:443` |
| `https://localhost:8412` | `172.16.2.12:443` |
| `https://localhost:8413` | `172.16.2.13:443` |
| `https://localhost:8414` | `172.16.2.14:443` |
| `https://localhost:8415` | `172.16.2.15:443` |
| `https://localhost:8416` | `172.16.2.16:443` |
| `https://localhost:8417` | `172.16.2.17:443` |
| `https://localhost:8418` | `172.16.2.18:443` |
| `https://localhost:8419` | `172.16.2.19:443` |
| `https://localhost:8420` | `172.16.2.20:443` |
| `https://localhost:8421` | `172.16.2.21:443` |
| `https://localhost:8422` | `172.16.2.22:443` |
| `https://localhost:8423` | `172.16.2.23:443` |
| `https://localhost:8424` | `172.16.2.24:443` |
| `https://localhost:8425` | `172.16.2.25:443` |
| `https://localhost:8426` | `172.16.2.26:443` |
| `https://localhost:8427` | `172.16.2.27:443` |
| `https://localhost:8428` | `172.16.2.28:443` |

## compute-tray-1

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;c2</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp29 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;80&#58;03&#58;81</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp29 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;80&#58;03&#58;80</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp29 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;e1</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp1 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;80&#58;03&#58;5c</code> | gb300-02-sn5600-csl-01 | swp1s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;80&#58;03&#58;5d</code> | gb300-02-sn5600-csl-02 | swp1s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;80&#58;03&#58;6c</code> | gb300-02-sn5600-csl-01 | swp1s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;80&#58;03&#58;6d</code> | gb300-02-sn5600-csl-02 | swp1s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;e1&#58;48</code> | gb300-02-sn5600-pl1-gl-01 | swp1s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;e1&#58;49</code> | gb300-02-sn5600-pl2-gl-01 | swp1s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;e1&#58;78</code> | gb300-02-sn5600-pl1-gl-02 | swp1s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;e1&#58;79</code> | gb300-02-sn5600-pl2-gl-02 | swp1s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;a0&#58;c8</code> | gb300-02-sn5600-pl1-gl-03 | swp1s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;a0&#58;c9</code> | gb300-02-sn5600-pl2-gl-03 | swp1s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;a0&#58;f8</code> | gb300-02-sn5600-pl1-gl-04 | swp1s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;a0&#58;f9</code> | gb300-02-sn5600-pl2-gl-04 | swp1s0 | East / West |  |  |  |

## compute-tray-2

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;c0</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp30 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;d7</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp30 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;d6</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp30 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;d4</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp2 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;b2</code> | gb300-02-sn5600-csl-01 | swp1s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;b3</code> | gb300-02-sn5600-csl-02 | swp1s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;c2</code> | gb300-02-sn5600-csl-01 | swp1s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;c3</code> | gb300-02-sn5600-csl-02 | swp1s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;0d&#58;08</code> | gb300-02-sn5600-pl1-gl-01 | swp1s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;0d&#58;09</code> | gb300-02-sn5600-pl2-gl-01 | swp1s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;0d&#58;38</code> | gb300-02-sn5600-pl1-gl-02 | swp1s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;0d&#58;39</code> | gb300-02-sn5600-pl2-gl-02 | swp1s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;c5&#58;88</code> | gb300-02-sn5600-pl1-gl-03 | swp1s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;c5&#58;89</code> | gb300-02-sn5600-pl2-gl-03 | swp1s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;c5&#58;b8</code> | gb300-02-sn5600-pl1-gl-04 | swp1s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;c5&#58;b9</code> | gb300-02-sn5600-pl2-gl-04 | swp1s1 | East / West |  |  |  |

## compute-tray-3

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;ba</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp31 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;91</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp31 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;90</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp31 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;ff</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp3 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;6c</code> | gb300-02-sn5600-csl-01 | swp2s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;6d</code> | gb300-02-sn5600-csl-02 | swp2s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;7c</code> | gb300-02-sn5600-csl-01 | swp2s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;7d</code> | gb300-02-sn5600-csl-02 | swp2s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;ec&#58;46</code> | gb300-02-sn5600-pl1-gl-01 | swp2s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;ec&#58;47</code> | gb300-02-sn5600-pl2-gl-01 | swp2s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;ec&#58;76</code> | gb300-02-sn5600-pl1-gl-02 | swp2s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;ec&#58;77</code> | gb300-02-sn5600-pl2-gl-02 | swp2s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;2b&#58;48</code> | gb300-02-sn5600-pl1-gl-03 | swp2s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;2b&#58;49</code> | gb300-02-sn5600-pl2-gl-03 | swp2s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;2b&#58;78</code> | gb300-02-sn5600-pl1-gl-04 | swp2s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;2b&#58;79</code> | gb300-02-sn5600-pl2-gl-04 | swp2s0 | East / West |  |  |  |

## compute-tray-4

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;ca</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp32 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;fd</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp32 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;fc</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp32 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;dc</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp4 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;d8</code> | gb300-02-sn5600-csl-01 | swp2s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;d9</code> | gb300-02-sn5600-csl-02 | swp2s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;e8</code> | gb300-02-sn5600-csl-01 | swp2s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;e9</code> | gb300-02-sn5600-csl-02 | swp2s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a3&#58;46</code> | gb300-02-sn5600-pl1-gl-01 | swp2s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a3&#58;47</code> | gb300-02-sn5600-pl2-gl-01 | swp2s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a3&#58;76</code> | gb300-02-sn5600-pl1-gl-02 | swp2s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a3&#58;77</code> | gb300-02-sn5600-pl2-gl-02 | swp2s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a5&#58;46</code> | gb300-02-sn5600-pl1-gl-03 | swp2s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a5&#58;47</code> | gb300-02-sn5600-pl2-gl-03 | swp2s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a5&#58;76</code> | gb300-02-sn5600-pl1-gl-04 | swp2s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a5&#58;77</code> | gb300-02-sn5600-pl2-gl-04 | swp2s1 | East / West |  |  |  |

## compute-tray-5

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;cc</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp33 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;6b</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp33 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;6a</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp33 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;05</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp5 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;46</code> | gb300-02-sn5600-csl-01 | swp3s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;47</code> | gb300-02-sn5600-csl-02 | swp3s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;56</code> | gb300-02-sn5600-csl-01 | swp3s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;c3&#58;57</code> | gb300-02-sn5600-csl-02 | swp3s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e1&#58;06</code> | gb300-02-sn5600-pl1-gl-01 | swp3s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e1&#58;07</code> | gb300-02-sn5600-pl2-gl-01 | swp3s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e1&#58;36</code> | gb300-02-sn5600-pl1-gl-02 | swp3s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e1&#58;37</code> | gb300-02-sn5600-pl2-gl-02 | swp3s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;48</code> | gb300-02-sn5600-pl1-gl-03 | swp3s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;49</code> | gb300-02-sn5600-pl2-gl-03 | swp3s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;78</code> | gb300-02-sn5600-pl1-gl-04 | swp3s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;79</code> | gb300-02-sn5600-pl2-gl-04 | swp3s0 | East / West |  |  |  |

## compute-tray-6

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;b8</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp34 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;ef</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp34 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;ee</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp34 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;00</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp6 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;ca</code> | gb300-02-sn5600-csl-01 | swp3s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;cb</code> | gb300-02-sn5600-csl-02 | swp3s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;da</code> | gb300-02-sn5600-csl-01 | swp3s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;db</code> | gb300-02-sn5600-csl-02 | swp3s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e7&#58;46</code> | gb300-02-sn5600-pl1-gl-01 | swp3s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e7&#58;47</code> | gb300-02-sn5600-pl2-gl-01 | swp3s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e7&#58;76</code> | gb300-02-sn5600-pl1-gl-02 | swp3s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e7&#58;77</code> | gb300-02-sn5600-pl2-gl-02 | swp3s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;fd&#58;08</code> | gb300-02-sn5600-pl1-gl-03 | swp3s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;fd&#58;09</code> | gb300-02-sn5600-pl2-gl-03 | swp3s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;fd&#58;38</code> | gb300-02-sn5600-pl1-gl-04 | swp3s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;fd&#58;39</code> | gb300-02-sn5600-pl2-gl-04 | swp3s1 | East / West |  |  |  |

## compute-tray-7

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;56</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp35 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;85</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp35 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;84</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp35 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;13</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp7 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;60</code> | gb300-02-sn5600-csl-01 | swp4s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;61</code> | gb300-02-sn5600-csl-02 | swp4s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;70</code> | gb300-02-sn5600-csl-01 | swp4s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;71</code> | gb300-02-sn5600-csl-02 | swp4s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;86</code> | gb300-02-sn5600-pl1-gl-01 | swp4s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;87</code> | gb300-02-sn5600-pl2-gl-01 | swp4s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;b6</code> | gb300-02-sn5600-pl1-gl-02 | swp4s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;b7</code> | gb300-02-sn5600-pl2-gl-02 | swp4s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;ca&#58;06</code> | gb300-02-sn5600-pl1-gl-03 | swp4s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;ca&#58;07</code> | gb300-02-sn5600-pl2-gl-03 | swp4s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;ca&#58;36</code> | gb300-02-sn5600-pl1-gl-04 | swp4s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;ca&#58;37</code> | gb300-02-sn5600-pl2-gl-04 | swp4s0 | East / West |  |  |  |

## compute-tray-8

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;26</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp36 | BMC |  |  |  |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;80&#58;1b&#58;67</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp36 |  |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;80&#58;1b&#58;66</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp36 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;06</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp8 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;80&#58;1b&#58;42</code> | gb300-02-sn5600-csl-01 | swp4s1 | Storage LACP |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;80&#58;1b&#58;43</code> | gb300-02-sn5600-csl-02 | swp4s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;80&#58;1b&#58;52</code> | gb300-02-sn5600-csl-01 | swp4s1 |  |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;80&#58;1b&#58;53</code> | gb300-02-sn5600-csl-02 | swp4s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;05&#58;c8</code> | gb300-02-sn5600-pl1-gl-01 | swp4s1 | East / West |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;05&#58;c9</code> | gb300-02-sn5600-pl2-gl-01 | swp4s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;05&#58;f8</code> | gb300-02-sn5600-pl1-gl-02 | swp4s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;05&#58;f9</code> | gb300-02-sn5600-pl2-gl-02 | swp4s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;69&#58;c8</code> | gb300-02-sn5600-pl1-gl-03 | swp4s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;69&#58;c9</code> | gb300-02-sn5600-pl2-gl-03 | swp4s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;69&#58;f8</code> | gb300-02-sn5600-pl1-gl-04 | swp4s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;69&#58;f9</code> | gb300-02-sn5600-pl2-gl-04 | swp4s1 | East / West |  |  |  |

## compute-tray-9

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;c6</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp37 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;bb&#58;43</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp37 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bb&#58;42</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp37 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;de</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp9 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bb&#58;1e</code> | gb300-02-sn5600-csl-01 | swp5s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bb&#58;1f</code> | gb300-02-sn5600-csl-02 | swp5s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bb&#58;2e</code> | gb300-02-sn5600-csl-01 | swp5s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bb&#58;2f</code> | gb300-02-sn5600-csl-02 | swp5s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;c8</code> | gb300-02-sn5600-pl1-gl-01 | swp5s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;c9</code> | gb300-02-sn5600-pl2-gl-01 | swp5s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;f8</code> | gb300-02-sn5600-pl1-gl-02 | swp5s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;b6&#58;f9</code> | gb300-02-sn5600-pl2-gl-02 | swp5s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;1c&#58;88</code> | gb300-02-sn5600-pl1-gl-03 | swp5s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;1c&#58;89</code> | gb300-02-sn5600-pl2-gl-03 | swp5s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;1c&#58;b8</code> | gb300-02-sn5600-pl1-gl-04 | swp5s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;1c&#58;b9</code> | gb300-02-sn5600-pl2-gl-04 | swp5s0 | East / West |  |  |  |

## compute-tray-10

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;ce</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp38 | BMC |  |  |  |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;80&#58;16&#58;cd</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp38 |  |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;80&#58;16&#58;cc</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp38 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;11</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp10 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;80&#58;16&#58;a8</code> | gb300-02-sn5600-csl-01 | swp5s1 | Storage LACP |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;80&#58;16&#58;a9</code> | gb300-02-sn5600-csl-02 | swp5s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;80&#58;16&#58;b8</code> | gb300-02-sn5600-csl-01 | swp5s1 |  |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;80&#58;16&#58;b9</code> | gb300-02-sn5600-csl-02 | swp5s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;48&#58;c8</code> | gb300-02-sn5600-pl1-gl-01 | swp5s1 | East / West |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;48&#58;c9</code> | gb300-02-sn5600-pl2-gl-01 | swp5s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;48&#58;f8</code> | gb300-02-sn5600-pl1-gl-02 | swp5s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;48&#58;f9</code> | gb300-02-sn5600-pl2-gl-02 | swp5s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;c9&#58;c6</code> | gb300-02-sn5600-pl1-gl-03 | swp5s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;c9&#58;c7</code> | gb300-02-sn5600-pl2-gl-03 | swp5s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;c9&#58;f6</code> | gb300-02-sn5600-pl1-gl-04 | swp5s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;c9&#58;f7</code> | gb300-02-sn5600-pl2-gl-04 | swp5s1 | East / West |  |  |  |

## compute-tray-11

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;bc</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp39 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7b&#58;26&#58;a9</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp39 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7b&#58;26&#58;a8</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp39 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;03</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp11 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7b&#58;26&#58;84</code> | gb300-02-sn5600-csl-01 | swp6s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7b&#58;26&#58;85</code> | gb300-02-sn5600-csl-02 | swp6s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7b&#58;26&#58;94</code> | gb300-02-sn5600-csl-01 | swp6s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7b&#58;26&#58;95</code> | gb300-02-sn5600-csl-02 | swp6s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;c6</code> | gb300-02-sn5600-pl1-gl-01 | swp6s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;c7</code> | gb300-02-sn5600-pl2-gl-01 | swp6s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;f6</code> | gb300-02-sn5600-pl1-gl-02 | swp6s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;a4&#58;f7</code> | gb300-02-sn5600-pl2-gl-02 | swp6s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;9d&#58;48</code> | gb300-02-sn5600-pl1-gl-03 | swp6s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;9d&#58;49</code> | gb300-02-sn5600-pl2-gl-03 | swp6s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;9d&#58;78</code> | gb300-02-sn5600-pl1-gl-04 | swp6s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;9d&#58;79</code> | gb300-02-sn5600-pl2-gl-04 | swp6s0 | East / West |  |  |  |

## compute-tray-12

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;24</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp40 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;b1</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp40 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;b0</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp40 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;10</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp12 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;8c</code> | gb300-02-sn5600-csl-01 | swp6s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;8d</code> | gb300-02-sn5600-csl-02 | swp6s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;9c</code> | gb300-02-sn5600-csl-01 | swp6s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;af&#58;9d</code> | gb300-02-sn5600-csl-02 | swp6s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;3d&#58;c8</code> | gb300-02-sn5600-pl1-gl-01 | swp6s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;3d&#58;c9</code> | gb300-02-sn5600-pl2-gl-01 | swp6s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;3d&#58;f8</code> | gb300-02-sn5600-pl1-gl-02 | swp6s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;3d&#58;f9</code> | gb300-02-sn5600-pl2-gl-02 | swp6s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;43&#58;88</code> | gb300-02-sn5600-pl1-gl-03 | swp6s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;43&#58;89</code> | gb300-02-sn5600-pl2-gl-03 | swp6s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;43&#58;b8</code> | gb300-02-sn5600-pl1-gl-04 | swp6s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;43&#58;b9</code> | gb300-02-sn5600-pl2-gl-04 | swp6s1 | East / West |  |  |  |

## compute-tray-13

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;be</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp41 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;b0&#58;e1</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp41 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;b0&#58;e0</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp41 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;aa</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp13 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;b0&#58;bc</code> | gb300-02-sn5600-csl-01 | swp7s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;b0&#58;bd</code> | gb300-02-sn5600-csl-02 | swp7s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;b0&#58;cc</code> | gb300-02-sn5600-csl-01 | swp7s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;b0&#58;cd</code> | gb300-02-sn5600-csl-02 | swp7s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;19&#58;08</code> | gb300-02-sn5600-pl1-gl-01 | swp7s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;19&#58;09</code> | gb300-02-sn5600-pl2-gl-01 | swp7s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;19&#58;38</code> | gb300-02-sn5600-pl1-gl-02 | swp7s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;19&#58;39</code> | gb300-02-sn5600-pl2-gl-02 | swp7s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;18&#58;48</code> | gb300-02-sn5600-pl1-gl-03 | swp7s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;18&#58;49</code> | gb300-02-sn5600-pl2-gl-03 | swp7s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;50&#58;18&#58;78</code> | gb300-02-sn5600-pl1-gl-04 | swp7s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;50&#58;18&#58;79</code> | gb300-02-sn5600-pl2-gl-04 | swp7s0 | East / West |  |  |  |

## compute-tray-14

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;c8</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp42 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;ab</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp42 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;aa</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp42 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;0e</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp14 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;86</code> | gb300-02-sn5600-csl-01 | swp7s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;87</code> | gb300-02-sn5600-csl-02 | swp7s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;96</code> | gb300-02-sn5600-csl-01 | swp7s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;ba&#58;97</code> | gb300-02-sn5600-csl-02 | swp7s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;1f&#58;88</code> | gb300-02-sn5600-pl1-gl-01 | swp7s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;1f&#58;89</code> | gb300-02-sn5600-pl2-gl-01 | swp7s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;1f&#58;b8</code> | gb300-02-sn5600-pl1-gl-02 | swp7s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;1f&#58;b9</code> | gb300-02-sn5600-pl2-gl-02 | swp7s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e8&#58;c6</code> | gb300-02-sn5600-pl1-gl-03 | swp7s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e8&#58;c7</code> | gb300-02-sn5600-pl2-gl-03 | swp7s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e8&#58;f6</code> | gb300-02-sn5600-pl1-gl-04 | swp7s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e8&#58;f7</code> | gb300-02-sn5600-pl2-gl-04 | swp7s1 | East / West |  |  |  |

## compute-tray-15

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b3&#58;d0</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp43 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;15</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp43 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;14</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp43 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;ae</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp15 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;f0</code> | gb300-02-sn5600-csl-01 | swp8s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bd&#58;f1</code> | gb300-02-sn5600-csl-02 | swp8s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;00</code> | gb300-02-sn5600-csl-01 | swp8s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;01</code> | gb300-02-sn5600-csl-02 | swp8s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;eb&#58;46</code> | gb300-02-sn5600-pl1-gl-01 | swp8s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;eb&#58;47</code> | gb300-02-sn5600-pl2-gl-01 | swp8s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;eb&#58;76</code> | gb300-02-sn5600-pl1-gl-02 | swp8s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;eb&#58;77</code> | gb300-02-sn5600-pl2-gl-02 | swp8s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;af&#58;48</code> | gb300-02-sn5600-pl1-gl-03 | swp8s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;af&#58;49</code> | gb300-02-sn5600-pl2-gl-03 | swp8s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;af&#58;78</code> | gb300-02-sn5600-pl1-gl-04 | swp8s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;af&#58;79</code> | gb300-02-sn5600-pl2-gl-04 | swp8s0 | East / West |  |  |  |

## compute-tray-16

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b3&#58;ce</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp44 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;bc&#58;bf</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp44 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bc&#58;be</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp44 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;0d</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp16 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bc&#58;9a</code> | gb300-02-sn5600-csl-01 | swp8s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bc&#58;9b</code> | gb300-02-sn5600-csl-02 | swp8s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;bc&#58;aa</code> | gb300-02-sn5600-csl-01 | swp8s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;bc&#58;ab</code> | gb300-02-sn5600-csl-02 | swp8s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;e6&#58;48</code> | gb300-02-sn5600-pl1-gl-01 | swp8s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;e6&#58;49</code> | gb300-02-sn5600-pl2-gl-01 | swp8s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;e6&#58;78</code> | gb300-02-sn5600-pl1-gl-02 | swp8s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;e6&#58;79</code> | gb300-02-sn5600-pl2-gl-02 | swp8s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;a7&#58;88</code> | gb300-02-sn5600-pl1-gl-03 | swp8s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;a7&#58;89</code> | gb300-02-sn5600-pl2-gl-03 | swp8s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4f&#58;a7&#58;b8</code> | gb300-02-sn5600-pl1-gl-04 | swp8s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4f&#58;a7&#58;b9</code> | gb300-02-sn5600-pl2-gl-04 | swp8s1 | East / West |  |  |  |

## compute-tray-17

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;1a</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp45 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;ad</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp45 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;ac</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp45 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;08&#58;c2</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp17 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;88</code> | gb300-02-sn5600-csl-01 | swp9s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;89</code> | gb300-02-sn5600-csl-02 | swp9s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;98</code> | gb300-02-sn5600-csl-01 | swp9s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7f&#58;be&#58;99</code> | gb300-02-sn5600-csl-02 | swp9s0 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;dc&#58;c6</code> | gb300-02-sn5600-pl1-gl-01 | swp9s0 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;dc&#58;c7</code> | gb300-02-sn5600-pl2-gl-01 | swp9s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;dc&#58;f6</code> | gb300-02-sn5600-pl1-gl-02 | swp9s0 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;dc&#58;f7</code> | gb300-02-sn5600-pl2-gl-02 | swp9s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;86&#58;46</code> | gb300-02-sn5600-pl1-gl-03 | swp9s0 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;86&#58;47</code> | gb300-02-sn5600-pl2-gl-03 | swp9s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;86&#58;76</code> | gb300-02-sn5600-pl1-gl-04 | swp9s0 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;86&#58;77</code> | gb300-02-sn5600-pl2-gl-04 | swp9s0 | East / West |  |  |  |

## compute-tray-18

| Component | MAC Address | Switch | Port | Usage | IP Address | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Tray BMC (AMI MegaRAC) | <code>18&#58;3d&#58;2d&#58;9b&#58;b4&#58;18</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp46 | BMC |  | admin / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| DPU BMC (BlueField OpenBMC) | <code>e0&#58;9d&#58;73&#58;7b&#58;13&#58;a9</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp46 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| DPU Host OOB (oob_net0) | <code>e0&#58;9d&#58;73&#58;7b&#58;13&#58;a8</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp46 |  |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host OOB (bond0 / enP5p9s0) | <code>c4&#58;ef&#58;bb&#58;1b&#58;09&#58;15</code> | gb300-02-sn2201dc-mgmt-sw-02 | swp18 | North / South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Tray Host N-S B3420 P1 via DPU (enP22s22f0np0) | <code>e0&#58;9d&#58;73&#58;7b&#58;13&#58;84</code> | gb300-02-sn5600-csl-01 | swp9s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Tray Host N-S B3420 P2 via DPU (enP22s22f1np1) | <code>e0&#58;9d&#58;73&#58;7b&#58;13&#58;85</code> | gb300-02-sn5600-csl-02 | swp9s1 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| DPU Host B3420 P1 (p0) | <code>e0&#58;9d&#58;73&#58;7b&#58;13&#58;94</code> | gb300-02-sn5600-csl-01 | swp9s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| DPU Host B3420 P2 (p1) | <code>e0&#58;9d&#58;73&#58;7b&#58;13&#58;95</code> | gb300-02-sn5600-csl-02 | swp9s1 |  |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 - DPU offload is currently disabled |
| Tray Host CX8 P1 lane1 (enp3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e0&#58;c6</code> | gb300-02-sn5600-pl1-gl-01 | swp9s1 | East / West |  |  | All East West interfaces are configured on a single vLAN.Note: You may hit ARP flux issues so please refer to the following document on steps to resolve this - https://docs.nvidia.com/dgx/dgx-os-7-user-guide/dgx-os-7-user-guide.pdf |
| Tray Host CX8 P1 lane2 (enp3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e0&#58;c7</code> | gb300-02-sn5600-pl2-gl-01 | swp9s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane1 (enP2p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;5d&#58;e0&#58;f6</code> | gb300-02-sn5600-pl1-gl-02 | swp9s1 | East / West |  |  |  |
| Tray Host CX8 P2 lane2 (enP2p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;5d&#58;e0&#58;f7</code> | gb300-02-sn5600-pl2-gl-02 | swp9s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane1 (enP16p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;e5&#58;48</code> | gb300-02-sn5600-pl1-gl-03 | swp9s1 | East / West |  |  |  |
| Tray Host CX8 P3 lane2 (enP16p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;e5&#58;49</code> | gb300-02-sn5600-pl2-gl-03 | swp9s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane1 (enP18p3s0f0np0) | <code>cc&#58;40&#58;f3&#58;4e&#58;e5&#58;78</code> | gb300-02-sn5600-pl1-gl-04 | swp9s1 | East / West |  |  |  |
| Tray Host CX8 P4 lane2 (enP18p3s0f1np1) | <code>cc&#58;40&#58;f3&#58;4e&#58;e5&#58;79</code> | gb300-02-sn5600-pl2-gl-04 | swp9s1 | East / West |  |  |  |

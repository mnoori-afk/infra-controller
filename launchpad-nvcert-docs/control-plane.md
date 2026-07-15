# Control Plane

Control-plane servers use BMCs for out-of-band management, 1G links for management access, CX7 links for storage, and CX7 links for north-south routing. Use the control-plane nodes as the primary place to set up and operate the environment after they are available.

For OS installation and network setup:

- Use north-south interfaces for inbound and outbound access.
- Use storage interfaces for WEKA access on the storage network.
- Follow the per-interface notes for subnet, gateway, and DNS details. BMC access, 1G management, storage, and north-south data links are distinct networks.
- Open BMC web interfaces with `https://<IP>`.

## control-plane-1

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;ce&#58;46</code> | gb300-02-sn2201-mg-01 | swp29 | BMC | https://172.16.0.28 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;64&#58;02</code> | gb300-02-sn2201-mg-01 | swp11 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;64&#58;03</code> | gb300-02-sn2201-mg-02 | swp11 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;c7&#58;f3&#58;7a</code> | gb300-02-sn5600-csl-01 | swp15s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;c7&#58;f3&#58;7b</code> | gb300-02-sn5600-csl-02 | swp15s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;ee&#58;1a</code> | gb300-02-sn5600-csl-01 | swp15s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;ee&#58;1b</code> | gb300-02-sn5600-csl-02 | swp15s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-2

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;ce&#58;41</code> | gb300-02-sn2201-mg-02 | swp29 | BMC | https://172.16.0.29 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;74&#58;e2</code> | gb300-02-sn2201-mg-01 | swp12 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;74&#58;e3</code> | gb300-02-sn2201-mg-02 | swp12 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;eb&#58;17&#58;c6</code> | gb300-02-sn5600-csl-01 | swp15s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;eb&#58;17&#58;c7</code> | gb300-02-sn5600-csl-02 | swp15s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;ea&#58;e4&#58;a2</code> | gb300-02-sn5600-csl-01 | swp15s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;ea&#58;e4&#58;a3</code> | gb300-02-sn5600-csl-02 | swp15s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-3

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9e&#58;38&#58;f0</code> | gb300-02-sn2201-mg-01 | swp30 | BMC | https://172.16.0.30 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;6d&#58;14</code> | gb300-02-sn2201-mg-01 | swp13 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;6d&#58;15</code> | gb300-02-sn2201-mg-02 | swp13 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;eb&#58;62&#58;26</code> | gb300-02-sn5600-csl-01 | swp16s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;eb&#58;62&#58;27</code> | gb300-02-sn5600-csl-02 | swp16s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;eb&#58;67&#58;e2</code> | gb300-02-sn5600-csl-01 | swp16s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;eb&#58;67&#58;e3</code> | gb300-02-sn5600-csl-02 | swp16s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-4

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;cd&#58;38</code> | gb300-02-sn2201-mg-02 | swp30 | BMC | https://172.16.0.31 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;93&#58;e4</code> | gb300-02-sn2201-mg-01 | swp14 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;93&#58;e5</code> | gb300-02-sn2201-mg-02 | swp14 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;c7&#58;5d&#58;6a</code> | gb300-02-sn5600-csl-01 | swp16s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;c7&#58;5d&#58;6b</code> | gb300-02-sn5600-csl-02 | swp16s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;1a&#58;ea</code> | gb300-02-sn5600-csl-01 | swp16s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;1a&#58;eb</code> | gb300-02-sn5600-csl-02 | swp16s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-5

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;ce&#58;87</code> | gb300-02-sn2201-mg-01 | swp31 | BMC | https://172.16.0.32 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;b7&#58;d2</code> | gb300-02-sn2201-mg-01 | swp15 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;b7&#58;d3</code> | gb300-02-sn2201-mg-02 | swp15 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;5b&#58;8a</code> | gb300-02-sn5600-csl-01 | swp17s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;5b&#58;8b</code> | gb300-02-sn5600-csl-02 | swp17s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;7f&#58;6a</code> | gb300-02-sn5600-csl-01 | swp17s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;7f&#58;6b</code> | gb300-02-sn5600-csl-02 | swp17s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-6

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;ce&#58;96</code> | gb300-02-sn2201-mg-02 | swp31 | BMC | https://172.16.0.33 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;62&#58;9a</code> | gb300-02-sn2201-mg-01 | swp16 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;62&#58;9b</code> | gb300-02-sn2201-mg-02 | swp16 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;48&#58;5a</code> | gb300-02-sn5600-csl-01 | swp17s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;48&#58;5b</code> | gb300-02-sn5600-csl-02 | swp17s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;c7&#58;5d&#58;8a</code> | gb300-02-sn5600-csl-01 | swp17s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;c7&#58;5d&#58;8b</code> | gb300-02-sn5600-csl-02 | swp17s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-7

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;e5&#58;ca</code> | gb300-02-sn2201-mg-01 | swp32 | BMC | https://172.16.0.34 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;b8&#58;e0</code> | gb300-02-sn2201-mg-01 | swp17 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;b8&#58;e1</code> | gb300-02-sn2201-mg-02 | swp17 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;ea&#58;e5&#58;32</code> | gb300-02-sn5600-csl-01 | swp18s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;ea&#58;e5&#58;33</code> | gb300-02-sn5600-csl-02 | swp18s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;d3&#58;71&#58;d6</code> | gb300-02-sn5600-csl-01 | swp18s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;d3&#58;71&#58;d7</code> | gb300-02-sn5600-csl-02 | swp18s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-8

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;ce&#58;be</code> | gb300-02-sn2201-mg-02 | swp32 | BMC | https://172.16.0.35 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;c6&#58;06</code> | gb300-02-sn2201-mg-01 | swp18 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;c6&#58;07</code> | gb300-02-sn2201-mg-02 | swp18 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;ed&#58;9a&#58;c2</code> | gb300-02-sn5600-csl-01 | swp18s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;ed&#58;9a&#58;c3</code> | gb300-02-sn5600-csl-02 | swp18s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;eb&#58;67&#58;d2</code> | gb300-02-sn5600-csl-01 | swp18s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;eb&#58;67&#58;d3</code> | gb300-02-sn5600-csl-02 | swp18s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-9

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;dd&#58;7d</code> | gb300-02-sn2201-mg-01 | swp33 | BMC | https://172.16.0.36 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;eb&#58;6e</code> | gb300-02-sn2201-mg-01 | swp19 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;eb&#58;6f</code> | gb300-02-sn2201-mg-02 | swp19 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;d3&#58;88&#58;c6</code> | gb300-02-sn5600-csl-01 | swp19s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;d3&#58;88&#58;c7</code> | gb300-02-sn5600-csl-02 | swp19s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;ed&#58;9c&#58;62</code> | gb300-02-sn5600-csl-01 | swp19s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;ed&#58;9c&#58;63</code> | gb300-02-sn5600-csl-02 | swp19s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-10

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;dd&#58;b4</code> | gb300-02-sn2201-mg-02 | swp33 | BMC | https://172.16.0.37 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;8e&#58;56</code> | gb300-02-sn2201-mg-01 | swp20 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;8e&#58;57</code> | gb300-02-sn2201-mg-02 | swp20 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;ea&#58;be&#58;b6</code> | gb300-02-sn5600-csl-01 | swp19s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;ea&#58;be&#58;b7</code> | gb300-02-sn5600-csl-02 | swp19s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;eb&#58;18&#58;76</code> | gb300-02-sn5600-csl-01 | swp19s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;eb&#58;18&#58;77</code> | gb300-02-sn5600-csl-02 | swp19s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-11

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;dd&#58;d7</code> | gb300-02-sn2201-mg-01 | swp34 | BMC | https://172.16.0.38 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;ae&#58;66</code> | gb300-02-sn2201-mg-01 | swp21 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;ae&#58;67</code> | gb300-02-sn2201-mg-02 | swp21 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;ea&#58;bf&#58;66</code> | gb300-02-sn5600-csl-01 | swp20s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;ea&#58;bf&#58;67</code> | gb300-02-sn5600-csl-02 | swp20s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;ea&#58;d5&#58;36</code> | gb300-02-sn5600-csl-01 | swp20s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;ea&#58;d5&#58;37</code> | gb300-02-sn5600-csl-02 | swp20s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-12

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;ce&#58;3c</code> | gb300-02-sn2201-mg-02 | swp34 | BMC | https://172.16.0.39 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;eb&#58;b6</code> | gb300-02-sn2201-mg-01 | swp22 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;eb&#58;b7</code> | gb300-02-sn2201-mg-02 | swp22 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;1b&#58;0a</code> | gb300-02-sn5600-csl-01 | swp20s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;1b&#58;0b</code> | gb300-02-sn5600-csl-02 | swp20s2 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;c8&#58;1a&#58;1a</code> | gb300-02-sn5600-csl-01 | swp20s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;c8&#58;1a&#58;1b</code> | gb300-02-sn5600-csl-02 | swp20s3 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

## control-plane-13

| Component | MAC Address | Switch | Port | Usage | Access / IP | User / Password | Notes |
|---|---|---|---|---|---|---|---|
| Control-plane BMC | <code>18&#58;3d&#58;2d&#58;9d&#58;cd&#58;fb</code> | gb300-02-sn2201-mg-01 | swp35 | BMC | https://172.16.0.40 | USERID / Buynvidia2026! |  |
| OS MGMT OCP P1 (ens6f0np0) | <code>6c&#58;83&#58;75&#58;25&#58;b4&#58;cc</code> | gb300-02-sn2201-mg-01 | swp23 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| OS MGMT OCP P2 (ens6f1np1) | <code>6c&#58;83&#58;75&#58;25&#58;b4&#58;cd</code> | gb300-02-sn2201-mg-02 | swp23 | 1G North South |  |  | Subnet is 172.16.2.x/24. Default GW is 172.16.2.1. DNS is 172.16.0.1 |
| Data CX7 SL1 P1 (ens1f0np0) | <code>8c&#58;91&#58;3a&#58;eb&#58;47&#58;d6</code> | gb300-02-sn5600-csl-01 | swp21s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL1 P2 (ens1f1np1) | <code>8c&#58;91&#58;3a&#58;eb&#58;47&#58;d7</code> | gb300-02-sn5600-csl-02 | swp21s0 | Storage LACP |  |  | Subnet is 172.16.5.x/24. |
| Data CX7 SL3 P1 (ens3f0np0) | <code>8c&#58;91&#58;3a&#58;d5&#58;d4&#58;9e</code> | gb300-02-sn5600-csl-01 | swp21s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |
| Data CX7 SL3 P2 (ens3f1np1) | <code>8c&#58;91&#58;3a&#58;d5&#58;d4&#58;9f</code> | gb300-02-sn5600-csl-02 | swp21s1 | North / South LACP |  |  | Subnet is 172.16.3.x/24. Default GW is 172.16.3.1. DNS is 172.16.0.1 |

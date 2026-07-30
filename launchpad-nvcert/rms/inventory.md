# nvcert rack `nvcert-r1` — verified component inventory

All values cross-checked against the nvcert hardware docs
(`launchpad-nvcert-docs/{nvlink-management,power-shelves}.md`), the live ToR bridge
MAC table (`gb300-02-sn2201dc-mgmt-sw-01`, 172.16.0.14), the nico-dhcp leases, and each
device's BMC Redfish. Schema/creds confirmed against the **working launchpad** deploy
(`nico_system_nico.expected_switches` / `expected_power_shelves`).

- Rack: **nvcert-r1** (profile NVL72_GB300), siteId `30b7f861-2b28-4da7-89b1-94d0e984457a`
- BMC MAC verification: nvcert's real BMC MACs = the doc values (`20:4d:52:d8:*` /
  `24:5b:f0:81:*`) — confirmed 3 ways (docs = ToR dynamic VLAN-200 entries = DHCP leases).
  (Unlike launchpad, where the portal BMC MACs were wrong; here they are correct.)

## 9 NVLink switches
- Model `N5500_LD`, manufacturer NVIDIA
- BMC: `root` / `Buynvidia2026!`   ·   NVOS: `admin` / `Buynvidia2026!`
- BMC MAC = `20:4d:52:d8:*` (DHCP-leased, hostname `gb300nvl-sw-bmc`)
- NVOS MAC = `60:5e:65:*` (the MGMT/`admin` interface per docs; not DHCP-leased pre-ingestion — expected)

| # | Serial | BMC MAC | NVOS MAC | BMC IP |
|---|---|---|---|---|
| 1 | MT2544602NNP | 20:4d:52:d8:87:fe | 60:5e:65:97:97:5e | 172.16.2.77 |
| 2 | MT2544602NHD | 20:4d:52:d8:5c:3e | 60:5e:65:ad:14:00 | 172.16.2.76 |
| 3 | MT2544602NH5 | 20:4d:52:d8:5a:3e | 60:5e:65:ac:b6:32 | 172.16.2.79 |
| 4 | MT2544602NHB | 20:4d:52:d8:5b:be | 60:5e:65:ac:b6:4a | 172.16.2.63 |
| 5 | MT2544602NJ8 | 20:4d:52:d8:63:3e | 60:5e:65:ad:25:78 | 172.16.2.82 |
| 6 | MT2544602NNM | 20:4d:52:d8:87:7e | 60:5e:65:97:8f:ae | 172.16.2.70 |
| 7 | MT2544602NH0 | 20:4d:52:d8:58:fe | 60:5e:65:ac:b6:5a | 172.16.2.75 |
| 8 | MT2544602NDA | 20:4d:52:d8:3a:7e | 60:5e:65:be:8c:ae | 172.16.2.78 |
| 9 | MT2544602NJC | 20:4d:52:d8:64:3e | 60:5e:65:97:98:be | 172.16.2.73 |

## 6 power shelves
- Model `PF-1333-7RB`, manufacturer LiteOn
- BMC: `root` / `0penBmc`   (verified working on the nvcert shelves via Redfish;
  launchpad used a different password — do NOT copy launchpad's here)
- No NVOS (power shelves have none)

| # | Serial | BMC MAC | BMC IP |
|---|---|---|---|
| 1 | 613337RBX04X15342TX | 24:5b:f0:81:e9:84 | 172.16.2.71 |
| 2 | 613337RBX04X15342TV | 24:5b:f0:81:e9:2f | 172.16.2.80 |
| 3 | 613337RBX04X15342U7 | 24:5b:f0:81:e7:ce | 172.16.2.81 |
| 4 | 613337RBX04X15342TU | 24:5b:f0:81:e6:9c | 172.16.2.74 |
| 5 | 613337RBX04X15342TY | 24:5b:f0:81:e9:87 | 172.16.2.72 |
| 6 | 613337RBX04X15342U2 | 24:5b:f0:81:e6:b4 | 172.16.2.68 |

## Ingestion method
admin-cli `expected-switch add` / `expected-power-shelf add` (writes directly to Core
`expected_switches` / `expected_power_shelves`, matching launchpad). See
`ingest-rack-components.sh` and README §"Rack component ingestion".

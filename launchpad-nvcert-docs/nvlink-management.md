# NVLink Management

> **Note**
>
> NVLink BMC and management interfaces are on the 172.16.2.x management network and are reached from the control-plane nodes. The platform documentation captures the MAC address, connected switch, port, and default credentials where those details are available.

## Documentation Links

NVLink switches use NVIDIA NVOS, not Cumulus Linux. Use NVOS documentation for NVLink switch software and operational commands.

| Area | Documentation | Use It For |
|---|---|---|
| NVOS user manual | [NVIDIA NVOS User Manual for NVLink Switches](https://docs.nvidia.com/networking/display/nvidianvosusermanualfornvlinkswitchesv25024282) | NVLink switch software management, NVUE, system management, user interfaces, and operational command guidance. |
| NVLink switching | [NVLink Switching](https://docs.nvidia.com/networking/display/nvidianvosusermanualfornvlinkswitchesv25024282/nvlink-switching) | NVLink interface, fabric, and cluster-management command references. |

> **Note**
>
> Do not use the Cumulus Linux switch commands from the Ethernet switch page on NVLink switches. NVLink switch management should follow the NVOS documentation.

## BMC Interfaces

| Server | MAC Address | Switch | Port | User / Password | Notes |
|---|---|---|---|---|---|
| nvlink-switch-1-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;87&#58;fe</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp2 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-2-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;5c&#58;3e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp4 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-3-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;5a&#58;3e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp6 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-4-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;5b&#58;be</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp8 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-5-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;63&#58;3e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp10 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-6-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;87&#58;7e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp12 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-7-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;58&#58;fe</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp14 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-8-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;3a&#58;7e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp16 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-9-bmc | <code>20&#58;4d&#58;52&#58;d8&#58;64&#58;3e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp18 | root / Buynvidia2026! | BMC is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |

## Management Interfaces

| Server | MAC Address | Switch | Port | User / Password | Notes |
|---|---|---|---|---|---|
| nvlink-switch-1 | <code>60&#58;5e&#58;65&#58;97&#58;97&#58;5e</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp1 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-2 | <code>60&#58;5e&#58;65&#58;ad&#58;14&#58;00</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp3 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-3 | <code>60&#58;5e&#58;65&#58;ac&#58;b6&#58;32</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp5 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-4 | <code>60&#58;5e&#58;65&#58;ac&#58;b6&#58;4a</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp7 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-5 | <code>60&#58;5e&#58;65&#58;ad&#58;25&#58;78</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp9 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-6 | <code>60&#58;5e&#58;65&#58;97&#58;8f&#58;ae</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp11 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-7 | <code>60&#58;5e&#58;65&#58;ac&#58;b6&#58;5a</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp13 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-8 | <code>60&#58;5e&#58;65&#58;be&#58;8c&#58;ae</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp15 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| nvlink-switch-9 | <code>60&#58;5e&#58;65&#58;97&#58;98&#58;be</code> | gb300-02-sn2201dc-mgmt-sw-01 | swp17 | admin / Buynvidia2026! | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |

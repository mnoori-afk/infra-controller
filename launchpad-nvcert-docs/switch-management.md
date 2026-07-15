# Switch Management

The switches below are reachable on the out-of-band management network.

> **Note**
>
> Switch changes can affect access to the full environment. If you are unsure what a command does, stop and review the NVIDIA documentation before changing interface, routing, bridge, VLAN, MLAG, or management settings.

## Documentation Links

The Ethernet switches in this environment run NVIDIA Cumulus Linux. Use the documentation that matches the installed Cumulus release when making changes.

| Area | Documentation | Use It For |
|---|---|---|
| Cumulus Linux | [NVIDIA Cumulus Linux User Guide](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux/) | Switch operating system concepts, interface configuration, routing, bridging, VLANs, services, monitoring, and troubleshooting. |
| NVUE CLI | [NVIDIA NVUE CLI](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux/System-Configuration/NVIDIA-User-Experience-NVUE/NVUE-CLI/) | Understanding the `nv` command model before making Cumulus Linux configuration changes. |
| NVUE command reference | [NVIDIA NVUE Command Reference](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux/NVUE-Command-Reference/) | Checking exact command syntax for `nv show`, `nv set`, `nv unset`, `nv config`, and `nv action`. |
| SN5600 hardware | [NVIDIA Spectrum-4 SN5000 2U Switch Systems Hardware User Manual](https://docs.nvidia.com/networking/display/sn5000) | SN5600 platform details, ports, management interfaces, LEDs, cabling, FRUs, and hardware troubleshooting. |
| SN2201 management switches | [NVIDIA SN2201 and SN2201_M 1G Management Switch Systems User Manual](https://docs.nvidia.com/networking/display/sn2201switchesum) | SN2201 and SN2201_M platform details, management interfaces, cabling, LEDs, FRUs, and hardware troubleshooting. |

> **Note**
>
> Cumulus Linux supports both NVUE and lower-level Linux configuration workflows. Do not mix configuration methods on the same switch unless you are intentionally following a documented recovery or migration procedure.

## Switch Inventory

| Server | Component | MAC Address | Port | Usage | IP Address | User / Password |
|---|---|---|---|---|---|---|
| gb300-02-sn5600-csl-01 | Switch eth0 (OOB mgmt) | <code>e8&#58;9e&#58;49&#58;21&#58;5e&#58;66</code> | swp46 | North-South Spine (Collapsed Spine Leaf) | 172.16.0.10 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-csl-02 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;ca&#58;91&#58;2e</code> | swp46 | North-South Spine (Collapsed Spine Leaf) | 172.16.0.11 | cumulus / Buynvidia2026! |
| gb300-02-sn2201-mg-01 | Switch eth0 (OOB mgmt) | <code>fc&#58;6a&#58;1c&#58;01&#58;15&#58;30</code> | swp48 | North-South out of band switch | 172.16.0.12 | cumulus / Buynvidia2026! |
| gb300-02-sn2201-mg-02 | Switch eth0 (OOB mgmt) | <code>fc&#58;6a&#58;1c&#58;01&#58;18&#58;18</code> | swp48 | North-South out of band switch | 172.16.0.13 | cumulus / Buynvidia2026! |
| gb300-02-sn2201dc-mgmt-sw-01 | Switch eth0 (OOB mgmt) | <code>28&#58;01&#58;cd&#58;61&#58;d4&#58;58</code> | swp47 | North-South out of band switch | 172.16.0.14 | cumulus / Buynvidia2026! |
| gb300-02-sn2201dc-mgmt-sw-02 | Switch eth0 (OOB mgmt) | <code>28&#58;01&#58;cd&#58;61&#58;c0&#58;80</code> | swp47 | North-South out of band switch | 172.16.0.15 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl1-gs-01 | Switch eth0 (OOB mgmt) | <code>cc&#58;40&#58;f3&#58;07&#58;3b&#58;4c</code> | swp40 | East-West Spine Plane #1 | 172.16.0.16 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl1-gs-02 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;e7&#58;5b&#58;f2</code> | swp40 | East-West Spine Plane #1 | 172.16.0.17 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl1-gl-01 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;58&#58;d1&#58;16</code> | swp42 | East-West Leaf Plane #1 | 172.16.0.18 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl1-gl-02 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;3b&#58;a5&#58;72</code> | swp43 | East-West Leaf Plane #1 | 172.16.0.19 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl1-gl-03 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;d7&#58;b0&#58;30</code> | swp44 | East-West Leaf Plane #1 | 172.16.0.20 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl1-gl-04 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;e7&#58;5d&#58;52</code> | swp45 | East-West Leaf Plane #1 | 172.16.0.21 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl2-gs-01 | Switch eth0 (OOB mgmt) | <code>b8&#58;e9&#58;24&#58;1d&#58;9e&#58;72</code> | swp41 | East-West Spine Plane #2 | 172.16.0.22 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl2-gs-02 | Switch eth0 (OOB mgmt) | <code>38&#58;25&#58;f3&#58;93&#58;83&#58;ae</code> | swp41 | East-West Spine Plane #2 | 172.16.0.23 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl2-gl-01 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;ca&#58;78&#58;98</code> | swp42 | East-West Leaf Plane #2 | 172.16.0.24 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl2-gl-02 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;df&#58;b4&#58;fa</code> | swp43 | East-West Leaf Plane #2 | 172.16.0.25 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl2-gl-03 | Switch eth0 (OOB mgmt) | <code>90&#58;e3&#58;17&#58;a7&#58;53&#58;c8</code> | swp44 | East-West Leaf Plane #2 | 172.16.0.26 | cumulus / Buynvidia2026! |
| gb300-02-sn5600-pl2-gl-04 | Switch eth0 (OOB mgmt) | <code>d8&#58;94&#58;24&#58;d7&#58;b0&#58;60</code> | swp45 | East-West Leaf Plane #2 | 172.16.0.27 | cumulus / Buynvidia2026! |

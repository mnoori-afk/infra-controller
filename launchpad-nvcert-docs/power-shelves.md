# Power Shelves

Power shelf management interfaces are on the 172.16.2.x management network and are reached from the control-plane nodes.

| Server | Component | MAC Address | Switch | Port | User / Password | Notes |
|---|---|---|---|---|---|---|
| powershelf-1 | Power Shelf Control | <code>24&#58;5b&#58;f0&#58;81&#58;e9&#58;84</code> | gb300-02-sn2201-mg-01 | swp36 | root / 0penBmc | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| powershelf-2 | Power Shelf Control | <code>24&#58;5b&#58;f0&#58;81&#58;e9&#58;2f</code> | gb300-02-sn2201-mg-01 | swp37 | root / 0penBmc | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| powershelf-3 | Power Shelf Control | <code>24&#58;5b&#58;f0&#58;81&#58;e7&#58;ce</code> | gb300-02-sn2201-mg-01 | swp38 | root / 0penBmc | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| powershelf-4 | Power Shelf Control | <code>24&#58;5b&#58;f0&#58;81&#58;e6&#58;9c</code> | gb300-02-sn2201-mg-02 | swp36 | root / 0penBmc | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| powershelf-5 | Power Shelf Control | <code>24&#58;5b&#58;f0&#58;81&#58;e9&#58;87</code> | gb300-02-sn2201-mg-02 | swp37 | root / 0penBmc | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |
| powershelf-6 | Power Shelf Control | <code>24&#58;5b&#58;f0&#58;81&#58;e6&#58;b4</code> | gb300-02-sn2201-mg-02 | swp38 | root / 0penBmc | MGMT is set to DHCP and is listening on the 172.16.2.x network. These will get IPs from control plane nodes |

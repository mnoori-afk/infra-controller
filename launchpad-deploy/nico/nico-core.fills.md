# helm-prereqs/values/nico-core.yaml — launchpad fills

> ⚠️ STALE CHECKLIST — `nico/nico-core.launchpad.yaml` is the source of truth. Values below are
> historical; verify against the YAML.

Edit these fields in `helm-prereqs/values/nico-core.yaml` (leave others at template defaults).

## nico-api
- `nico-api.hostname`: `api-launchpad.nvidialaunchpad.internal`
- `nico-api.externalService.annotations."metallb.universe.tf/loadBalancerIPs"`: `172.16.2.40`
- `nico-api.certificate.extraDnsNames`: keep `carbide-api.forge`, `nico-api.forge`, … + add the hostname above.

## siteConfig TOML (nico-api.siteConfig.nicoApiSiteConfig)
```toml
sitename = "rg-forge-launchpad"
initial_domain_name = "api-launchpad.nvidialaunchpad.internal"
attestation_enabled = true
dhcp_servers = ["172.16.2.41"]                        # nico-dhcp VIP
route_servers = []
enable_route_servers = false
site_fabric_prefixes = ["172.16.4.128/25"]            # north-south / tenant fabric
deny_prefixes = []                                    # emptied on launchpad — do NOT deny mgmt underlay 172.16.2.0/24 (holds the VIPs)

[site_explorer]
run_interval = "30s"
[machine_validation_config]
enabled = true
[bom_validation]
enabled = true
ignore_unassigned_machines = true

[pools.lo-ip]
type = "ipv4"
ranges = [{ start = "172.16.3.16", end = "172.16.3.216" }]
[pools.vlan-id]
type = "integer"
ranges = [{ start = "2000", end = "3000" }]
[pools.vni]
type = "integer"
ranges = [{ start = "1024500", end = "1024800" }]
[pools.vpc-vni]
type = "integer"
ranges = [{ start = "60200", end = "60300" }]

[networks.admin]            # PLACEHOLDER — admin never allocates in NIC mode. Trays DHCP on launchpad-mgmt, NOT here.
type = "admin"
prefix = "172.16.4.0/25"
gateway = "172.16.4.1"
mtu = 1500
reserve_first = 5

[networks.launchpad-mgmt]   # VLAN 200 — where trays DHCP
type = "underlay"
prefix = "172.16.2.0/24"
gateway = "172.16.2.1"
mtu = 1500
reserve_first = 50          # CRITICAL: reserves .1–.50 so NICo never hands a tray a MetalLB VIP (.30–.49)

[networks.launchpad-ns]     # north-south data underlay
type = "underlay"
prefix = "172.16.3.0/24"
gateway = "172.16.3.1"
mtu = 1500
reserve_first = 2

[firmware_global]
autoupdate = false
no_reset_retries = true
[machine_state_controller]
failure_retry_time = "90m"
```

## Per-service VIPs (externalService loadBalancerIPs)
- nico-dhcp: `172.16.2.41`  | unbound: `172.16.2.42` | nico-pxe: `172.16.2.43`
- nico-ntp perPod: `172.16.2.44`, `172.16.2.45`, `172.16.2.46`
- nico-dns perPod: `172.16.2.47`, `172.16.2.48`
- nico-ssh-console-rs: `172.16.2.49`

## nico-dhcp kea hookParameters
- `nameservers: "172.16.2.42"`   (unbound — serves .forge)
- `ntpServer: "172.16.2.44,172.16.2.45,172.16.2.46"`
- `provisioningServer: "172.16.2.43"`   (nico-pxe)

## nico-pxe boot artifacts (aarch64 ONLY — Grace host + BF3 DPU)
```yaml
nico-pxe:
  bootArtifactContainers:
    - name: boot-artifacts-aarch64
      image: <registry>/boot-artifacts-aarch64:<tag>     # TODO: the available aarch64 image
      command: ["sh", "-c", "cp -r /aarch64 /apt /boot-artifacts/blobs/internal"]
```
(Do NOT add x86_64 — no x86 managed hosts. aarch64 image has no /firmware dir; copying it crash-loops.)

## unbound (.forge zone)
- `unbound.enabled: true`; `image`/`exporterImage` repo+tag (TODO).
- `unbound.externalService` VIP: `172.16.2.42`.
- `unbound.localConfig.forwarders.conf` forward-addr: `172.16.0.1`  (TODO confirm site resolver).
- `unbound.localData` → map each name to its VIP:
  - carbide-api.forge / nico-api.forge → `172.16.2.40`
  - carbide-pxe.forge / nico-pxe.forge / carbide-static-pxe.forge → `172.16.2.43`
  - carbide-ntp.forge / nico-ntp.forge → `172.16.2.44,172.16.2.45,172.16.2.46`
  - unbound.forge → `172.16.2.42`

## Also in the live YAML (not in this old checklist)
The current `nico-core.launchpad.yaml` additionally carries:
- `site_global_vpc_vni = 245002`; `datacenter_asn` + `[fnn.*]` + `[pools.fnn-asn]` (FNN/EVPN config).
- `[site_explorer]` `create_switches` / `create_power_shelves`, `explore_mode = "nv-redfish"`.
- `[machine_validation_config]` `tests = [...]` with `forge_DcgmFullLong` disabled.
- The rack blocks `[rack_profiles.NVL72_GB300]` / `[component_manager]` / `[rms]` (see RACK-CONFIG.md).
- The `nico-ssh-console-rs.configFiles.config` block (see SSH-CONSOLE.md).

## TODO before run
- `NICO_IMAGE_REGISTRY`, `NICO_CORE_IMAGE_TAG`, `REGISTRY_PULL_SECRET` (NGC), unbound + boot-artifacts tags.

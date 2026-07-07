# helm-prereqs/values/nico-core.yaml — launchpad fills

Edit these fields in `helm-prereqs/values/nico-core.yaml` (leave others at template defaults).

## nico-api
- `nico-api.hostname`: `api-launchpad.<your-domain>`  (TODO: confirm domain)
- `nico-api.externalService.annotations."metallb.universe.tf/loadBalancerIPs"`: `172.16.2.40`
- `nico-api.certificate.extraDnsNames`: keep `carbide-api.forge`, `nico-api.forge`, … + add the hostname above.

## siteConfig TOML (nico-api.siteConfig.nicoApiSiteConfig)
```toml
sitename = "rg-forge-launchpad"
initial_domain_name = "launchpad.<your-domain>"      # TODO confirm
attestation_enabled = false
dhcp_servers = ["172.16.2.41"]                        # nico-dhcp VIP
route_servers = []
enable_route_servers = false
site_fabric_prefixes = ["172.16.3.0/24"]              # north-south underlay
deny_prefixes = ["172.16.0.0/24", "172.16.2.0/24", "172.16.3.0/24", "172.16.5.0/24"]

[site_explorer]
run_interval = "30s"
[machine_validation_config]
enabled = true
[bom_validation]
enabled = true
ignore_unassigned_machines = true

[pools.lo-ip]   # dormant (DPU offload off) — small range ok
type = "ipv4"
ranges = [{ start = "172.16.3.240", end = "172.16.3.250" }]   # TODO confirm spare; or a 2nd-/24 carve later
[pools.vlan-id]
type = "integer"
ranges = [{ start = "100", end = "501" }]
[pools.vni]
type = "integer"
ranges = [{ start = "1024500", end = "1024800" }]
[pools.vpc-vni]
type = "integer"
ranges = [{ start = "0", end = "100" }]

[networks.admin]            # managed-host / inband — where trays DHCP
type = "admin"
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

## TODO before run
- `NICO_IMAGE_REGISTRY`, `NICO_CORE_IMAGE_TAG`, `REGISTRY_PULL_SECRET` (NGC), unbound + boot-artifacts tags.
- domain for hostname/initial_domain_name; unbound upstream resolver; lo-ip spare range.

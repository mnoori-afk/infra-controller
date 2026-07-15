# Architecture Overview

This page explains the practical access model for the GB300 NVL72 environment. The most important thing to understand is that the LaunchPad bastion is the entry point, but it is not the only operational hop. The bastion gives you documentation, access tooling, environment-scoped management services, and direct management reachability to the core network and control-plane BMC interfaces. From there, the control-plane nodes become the place where the environment is brought up, configured, and operated.

![GB300 NVL72 access path overview](assets/gb300-access-paths.svg?v=20260513)

## Access Model

| Layer | What It Provides | How You Use It |
|---|---|---|
| LaunchPad bastion | Documentation, desktop access, SSH console, and environment-scoped management services | Start here for environment orientation, system documentation, and direct access to core switch management and control-plane BMCs. |
| Core switches | North-south, storage, and fabric switching | Reachable from the bastion for management and troubleshooting. |
| Control-plane nodes | Primary operational hosts for environment setup | Use these nodes to build, configure, and manage the GB300 NVL72 environment after they are available. |
| Compute trays | GB300 compute resources | Accessible from the control-plane nodes, not directly from the bastion. |
| NVLink switches | Scale-up GPU fabric management | Accessible from the control-plane nodes, not directly from the bastion. |
| WEKA storage | Shared high-performance storage backing the environment | Reached by control-plane and compute tray nodes through their storage interfaces. |

## Network Roles

The environment has several network roles. Use these roles to decide which interface belongs in the OS installer, which path should carry storage traffic, and which links are only for management or internal system communication.

| Role | Purpose | What To Know During Setup |
|---|---|---|
| Management and BMC | Out-of-band access to switches and control-plane BMCs | The bastion can reach the core management layer and control-plane BMCs directly. Use this path to inspect, power, and bootstrap the environment. |
| North-south | Inbound and outbound access for installed systems | Use north-south interfaces for inbound and outbound access. Follow the interface notes for gateway and DNS details. |
| Storage | WEKA and storage-facing traffic | Control-plane nodes and compute tray nodes use their storage interfaces to reach WEKA storage. Do not treat storage links as general management paths. |
| East-west | Inter-compute tray communication | East-west interfaces are for system-internal compute fabric communication, not for bastion access. |

## Storage

The WEKA storage environment can be mounted with the native WEKA client or with NFS v4. Native WEKA client mounts must specify the storage interface created on the client host. NFS v4 mounts use `weka-nfs.nvidialaunchpad.internal` or the storage service IPs in `172.16.5.31-40`. WEKA provides the shared, high-performance storage layer for the environment so control-plane services and compute workloads can access a common data platform with low-latency, high-throughput storage paths.

Control-plane nodes and compute tray nodes both reach storage through their respective storage interfaces. Treat the storage network as a data path, separate from the out-of-band management and BMC paths.

## Bastion Reachability

From the bastion, you can access:

- Core switch management interfaces.
- Control-plane node BMC interfaces.
- Bastion-local documentation, desktop, SSH console, and environment-scoped management services.

> **Note**
>
> The bastion does not provide direct management reachability for every device in the environment. Compute tray management and NVLink switch management are reached from the control-plane nodes.

## Control-Plane Reachability

Use the control-plane nodes to set up and operate the environment. They are the bridge between the bastion-accessible management layer and the deeper system components.

From the control-plane nodes, you can access:

- Compute tray BMC and management paths.
- NVLink switch BMC and management paths.
- WEKA storage on the storage network.
- The services and tooling needed for environment bring-up.

## Recommended Workflow

1. Start on the LaunchPad bastion using the desktop or System Console.
2. Review the environment documentation and confirm the rendered hardware details.
3. Use the bastion to reach the core switches and control-plane BMC interfaces.
4. Bring up or validate the control-plane nodes.
5. Move operational work onto the control-plane nodes.
6. From the control-plane nodes, access compute tray management, NVLink switch management, and storage.
7. During OS installation, map each host's north-south, storage, and east-west interfaces before assigning routes or storage addresses.

## Where to Find Things

| Need | Start Here |
|---|---|
| Browser IDE and bastion file workspace | [Code Server IDE](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/coder/) |
| Bastion desktop access | [Desktop Environment](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/desktop) |
| Bastion terminal access | [System Console](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/console/) |
| Credentials, SSH keys, and bastion file transfer | [Access and Networks](access-and-networks.md) |
| Core switch management details | [Switch Management](switch-management.md) |
| WEKA storage service range | [WEKA Storage](storage.md) |
| Control-plane BMC and interface mapping | [Control Plane](control-plane.md) |
| Compute tray management and storage links | [Compute Trays](compute-trays.md) |
| NVLink BMC and management interfaces | [NVLink Management](nvlink-management.md) |

## Important Boundaries

> **Note**
>
> The bastion can access core switch management and control-plane BMC interfaces. Compute tray management and NVLink switch management are accessed from the control-plane nodes.

> **Note**
>
> Control-plane nodes and compute tray nodes both access WEKA storage through their storage interfaces. North-south interfaces carry inbound and outbound access; east-west interfaces are for inter-compute tray communication.

> **Note**
>
> Follow the per-interface notes for gateway and DNS details. Management-side defaults use `172.16.0.1` unless your deployment plan intentionally overrides them.

> **Note**
>
> This LaunchPad experience prepares the bastion and documentation without forcing an OS installation on the GB300 NVL72 hardware.

# Access and Networks

Use this page as the starting point for GB300 NVL72 management access. The tables in this documentation are rendered for the environment you are accessing.

Gateway, DNS, and subnet details are called out per interface where they matter. BMC and switch management live on `172.16.0.x`; host management and data interfaces use the subnet listed in each row. Open BMC web interfaces with `https://<IP>`.

## Credential Profiles

| Profile | Applies To | Username | Password |
|---|---|---|---|
| Cumulus switch OOB | SN5600, SN2201, and SN2201DC switch management | cumulus | Buynvidia2026! |
| Control-plane BMC | Control-plane server BMCs | USERID | Buynvidia2026! |
| Compute tray BMC | Compute tray AMI MegaRAC BMCs | admin | Buynvidia2026! |
| NVLink BMC | NVLink switch BMCs | root | Buynvidia2026! |
| NVLink management | NVLink switch management interfaces | admin | Buynvidia2026! |

For switch commands, platform manuals, and vendor documentation links, start with [Switch Management](switch-management.md#documentation-links). For NVLink switch software guidance, use [NVLink Management](nvlink-management.md#documentation-links).

## Network Summary

| Network | Purpose | Notes |
|---|---|---|
| `172.16.0.x` | Bastion, core switch management, and BMC access | Use `172.16.0.1` for gateway and DNS unless directed otherwise. |
| `172.16.2.x` | Host management and tray OOB north-south interfaces | Use `172.16.2.1` for the gateway and `172.16.0.1` for DNS where called out in the interface notes. |
| `172.16.3.x` | Control-plane north-south data interfaces | North-south links provide inbound and outbound access for installed systems. |
| `172.16.5.x` | Storage LACP network | Used by control-plane and compute-tray storage links. Native WEKA clients must bind to the storage interface; NFS v4 mounts use `weka-nfs.nvidialaunchpad.internal` or `172.16.5.31-40`. |

## Interface Roles

| Role | Meaning |
|---|---|
| BMC / OOB | Out-of-band management. Use `https://<IP>` for browser access, including power control, remote console, virtual media, and device management. |
| North / South | Inbound and outbound system access. Use these interfaces for the primary route. |
| Storage LACP | Storage-facing links used to reach WEKA. Keep storage traffic on these interfaces. |
| East / West | Inter-compute tray communication. These are system-internal compute fabric links. |

## Naming Conventions

| Prefix | Meaning |
|---|---|
| `gb300-02-sn5600-csl-*` | Collapsed spine leaf switches for north-south and storage paths. |
| `gb300-02-sn2201-mg-*` | Out-of-band management switches for control-plane nodes. |
| `gb300-02-sn2201dc-mgmt-sw-*` | Out-of-band management switches for compute trays. |
| `gb300-02-sn5600-pl1-*` | East-west fabric plane 1. |
| `gb300-02-sn5600-pl2-*` | East-west fabric plane 2. |
| `control-plane-*` | Control-plane servers. |
| `gb300-02-weka-*` | WEKA storage hosts. |
| `compute-tray-*` | GB300 compute trays. |
| `nvlink-switch-*` | NVLink switch management interfaces. |

## Primary Access Links

- [Code Server IDE](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/coder/)
- [Desktop Environment](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/desktop)
- [System Console](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/console/)

## User Access

Additional users can be given access to this environment by adding their registered LaunchPad email address to the deployment user list. Open the **Resources** dropdown at the top of the LaunchPad page, then select **User Management**. Use the same email address the user signs in with; access is tied to that LaunchPad identity.

After a user is added, they can open the LaunchPad experience, use the resource links on this page, and run **Resources > SSH Setup** for their own public key and current public IP address.

> **Note**
>
> SSH access is configured per user and per source IP. Each user should run **Resources > SSH Setup** themselves, and should repeat it whenever their public IP address changes.

## Bastion Workspace Tools

Use the bastion as the staging point for environment setup. Code Server is usually the easiest place to edit notes, inspect generated files, run shell commands, and stage scripts without leaving the browser.

| Tool | Link | Use It For |
|---|---|---|
| Code Server IDE | [Open Code Server](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/coder/) | Browser-based VS Code workspace, integrated terminal, file editing, small file upload/download |
| Desktop Environment | [Open Desktop](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/desktop) | Full graphical desktop access when browser IDE or terminal access is not enough |
| System Console | [Open System Console](https://de545178-d615-cf16-fa42-9b5c1034064c.nvidialaunchpad.com/launch/console/) | Browser-based terminal access to the bastion |

Code Server supports normal VS Code file editing and an integrated terminal. For small files, use the Code Server file explorer upload/download actions. For larger artifacts such as ISOs, drivers, firmware bundles, or OS media, use direct SSH access after completing **Resources > SSH Setup**, or pull from an internal web/object store from a bastion terminal.

Useful references:

- [code-server documentation](https://coder.com/docs/code-server/guide)
- [code-server GitHub project](https://github.com/coder/code-server)

## SSH Key Access

> **Note**
>
> To access the bastion directly from your workstation, open the **Resources** dropdown at the top of the LaunchPad page, then select **SSH Setup**. Do not edit `authorized_keys` directly on the bastion. The setup workflow adds your public key and creates the required firewall rule for your current public IP address.

Use the public key only, usually the file ending in `.pub`. A typical local command to print it is:

```bash
cat ~/.ssh/id_rsa.pub
```

In the **SSH Setup** dialog:

1. Paste your public SSH key.
2. Confirm the detected **IP Address** is the public IP you will connect from.
3. Select **Add Key**.
4. Use the SSH command shown in the success modal.

> **Note**
>
> The firewall rule is specific to the IP address entered in the dialog. If your workstation moves networks, your VPN changes egress IPs, or your public IP changes for any reason, run **Resources > SSH Setup** again before trying to connect.

## Copying Files to the Bastion

Complete **Resources > SSH Setup** first, then use the same host and user shown in the success modal for file transfers.

Create a staging directory on the bastion:

```bash
mkdir -p ~/uploads/isos
```

From your workstation, copy an ISO or other local artifact using the host shown in the SSH setup modal:

```bash
scp ./example.iso nvidia@<bastion-host-or-ip-from-setup-ssh>:~/uploads/isos/
```

For resumable or repeated transfers, use `rsync`:

```bash
rsync -avP ./example.iso nvidia@<bastion-host-or-ip-from-setup-ssh>:~/uploads/isos/
```

If `scp` or `rsync` stops working after it previously succeeded, rerun **Resources > SSH Setup** and confirm the IP address in the dialog matches your current public IP. After upload, use the bastion terminal to verify the file and move it into the final service path if your installation workflow requires one.

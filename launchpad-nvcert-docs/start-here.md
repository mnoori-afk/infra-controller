# Start Here

This environment gives you a prepared LaunchPad bastion for a GB300 NVL72 system. The bastion is your entry point. Your first job is to identify the control-plane BMC addresses, set up your own SSH access, stage any installation media, and then use the control-plane BMC console to install or bring up the control-plane operating system.

## First Five Minutes

1. Open this documentation from the LaunchPad environment.
2. Go to [Control Plane](control-plane.md) and find the `control-plane-*` BMC access URLs.
3. Open **Resources > SSH Setup** in LaunchPad.
4. Add your public SSH key and confirm the detected source IP address.
5. Use the SSH command shown by LaunchPad to connect to the bastion.
6. Copy any ISO, driver bundle, or install artifact to the bastion.
7. Open the control-plane BMC in a browser from the bastion desktop.
8. Mount the ISO through the BMC remote console or virtual media workflow.
9. Install the OS on the control-plane node.
10. Repeat the same path for the other control-plane nodes you need to bring up.

## Find the Control-Plane BMC URLs

Start with [Control Plane](control-plane.md). Look for rows where the usage is `BMC`.

Open BMC web interfaces with `https://<IP>`. The Control Plane table renders those BMC targets as `https://172.16.0.x` URLs for remote console, power control, and virtual media. The default control-plane BMC credential profile is listed in [Access and Networks](access-and-networks.md#credential-profiles).

The bastion can reach the control-plane BMC network directly. Your workstation usually cannot. Use the bastion desktop or a browser session inside the environment when opening those BMC addresses.

## Set Up SSH Before Uploading Files

If you need to upload an ISO or other local artifact, set up SSH first.

Open **Resources > SSH Setup** in LaunchPad, paste your public key, confirm the source IP address, and add the key. Use the SSH command shown in the success modal.

If your public IP address changes, run **Resources > SSH Setup** again. This includes changing networks, changing VPN egress, moving between home and office, or reconnecting through a different gateway.

## Copy ISOs and Artifacts to the Bastion

After SSH setup succeeds, create a staging directory on the bastion:

```bash
mkdir -p ~/uploads/isos
```

From your workstation, copy the ISO or artifact using the host shown by **SSH Setup**:

```bash
scp ./example.iso nvidia@<bastion-host-or-ip-from-setup-ssh>:~/uploads/isos/
```

For large or repeated transfers, `rsync` is easier to resume:

```bash
rsync -avP ./example.iso nvidia@<bastion-host-or-ip-from-setup-ssh>:~/uploads/isos/
```

You can then access the file from the bastion desktop, Code Server terminal, or System Console.

## Install Through the Control-Plane BMC

Use the bastion desktop to open the control-plane BMC URL from the [Control Plane](control-plane.md) table.

From the BMC:

1. Open the remote console.
2. Attach or mount the ISO through virtual media.
3. Boot the control-plane node to the mounted media.
4. Install the operating system.
5. Use the interface notes in [Control Plane](control-plane.md) and [Access and Networks](access-and-networks.md) for subnet, gateway, and DNS details.

After the control-plane nodes are available, use them as the operational hop for deeper system work such as compute tray management, NVLink switch management, and storage validation.

## Where To Go Next

| Task | Page |
|---|---|
| Find BMC URLs and interface mappings | [Control Plane](control-plane.md) |
| Confirm credentials and SSH setup | [Access and Networks](access-and-networks.md) |
| Understand the access model | [Architecture Overview](architecture-overview.md) |
| Mount WEKA storage | [WEKA Storage](storage.md) |
| Work with compute tray management | [Compute Trays](compute-trays.md) |
| Work with NVLink switch management | [NVLink Management](nvlink-management.md) |

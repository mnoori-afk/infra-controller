# WEKA Storage

WEKA provides the shared high-performance storage layer for the environment. Linux clients can mount storage through either the native WEKA filesystem client or NFS v4. Control-plane nodes and compute trays reach storage through their storage interfaces.

Use the storage interfaces on the control-plane nodes and compute trays when connecting to WEKA. Treat this as a storage data path, separate from north-south host routing, management addresses, BMC addresses, and east-west compute fabric traffic.

## Storage Access

| Method | Mount Target | Access Path |
|---|---|---|
| Native WEKA client | `172.16.5.11,172.16.5.12/gb300-weka_fs` | Use the storage interface created on the client host. |
| NFS v4 | `weka-nfs.nvidialaunchpad.internal:/gb300-weka_fs` (`172.16.5.31-40`) | Use the storage interface path. |

## Native WEKA Client

Install the WEKA client from the storage service, create the mount point, and specify the storage interface or bond you created with `-o net=...`. Use the core list for the type of system you are mounting from.

```bash
curl http://weka-nfs.nvidialaunchpad.internal:14000/dist/v1/install | WEKA_CGROUPS_MODE=force_v2 sh

mkdir -p /mnt/weka
```

### Compute Trays

```bash
mount -t wekafs \
  -o core=72,73,74,75,76,77,78,79 \
  -o net=bond1 \
  172.16.5.11,172.16.5.12/gb300-weka_fs \
  /mnt/weka
```

### Control-Plane Nodes

```bash
mount -t wekafs \
  -o core=88,89,90,91,92,93,94,95 \
  -o net=bond1 \
  172.16.5.11,172.16.5.12/gb300-weka_fs \
  /mnt/weka
```

In the examples above, `bond1` is the storage interface. Replace it with the interface or bond name created on your client if your configuration uses a different name.

## NFS v4

NFS mounts should use the `weka-nfs.nvidialaunchpad.internal` host record, which resolves to the storage service IPs in `172.16.5.31-40`. Do not mount through WEKA management or BMC addresses.

```bash
mkdir -p /mnt/weka_nfs

mount -t nfs weka-nfs.nvidialaunchpad.internal:/gb300-weka_fs /mnt/weka_nfs
```

## Client Software

Use only the native WEKA client or the NFS v4 mount path documented above. SMB access is not enabled for this environment.

| Need | Link |
|---|---|
| Download WEKA installation packages | [get.weka.io package workflow](https://docs.weka.io/planning-and-installation/bare-metal/obtaining-the-weka-install-file) |
| Add Linux WEKA clients | [Add clients to a bare-metal cluster](https://docs.weka.io/planning-and-installation/bare-metal/adding-clients-bare-metal) |

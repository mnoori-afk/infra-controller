# Single-node k3s (dev/test)

`setup.sh --single-node-k3s` installs the full NICo prerequisite stack on a
**single-node k3s cluster**. This mode is intended for development and testing
(e.g. running the whole stack plus machine-a-tron on one box); production
deployments should use the default 3-node HA path.

What the flag changes — and nothing else (without it, behavior is identical to
the normal install):

| Area | Default (3-node HA) | `--single-node-k3s` |
|---|---|---|
| Preflight node check | ≥ 3 schedulable nodes | ≥ 1 (`NICO_MIN_NODES` overridable), plus k3s sanity checks (server is k3s, built-in local-path present, ServiceLB not active) |
| local-path-provisioner | Bundled manifest installed into `local-path-storage` | Skipped — k3s's built-in provisioner is used (installing both would race on every PVC). The `local-path-persistent` (Retain) StorageClass is still created. |
| Vault | HA Raft, 3 replicas, required podAntiAffinity | 1 replica, anti-affinity dropped (`unseal_vault.sh` adapts automatically) |
| PostgreSQL (nico-pg-cluster) | 3-instance Patroni cluster | 1 instance |
| `clean.sh` | Removes the bundled provisioner | Leaves the k3s built-in provisioner and its `local-path` StorageClass untouched |

Everything that is *values-driven* stays your responsibility, exactly as in the
normal install: a MetalLB **L2** config (see below), site values in
`values/nico-core.yaml`, `siteName` in `values.yaml`, etc.

## Installing k3s

k3s must be installed with **ServiceLB disabled** (it would fight MetalLB for
`LoadBalancer` services) and Traefik disabled (unused; avoids port squatting).

```bash
# Pin the k3s version and verify the bootstrap script before piping to sh.
K3S_VERSION="v1.36.1+k3s1"

curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
sha256sum /tmp/k3s-install.sh    # audit/compare before running as root

sudo INSTALL_K3S_VERSION="${K3S_VERSION}" \
     INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --write-kubeconfig-mode 644" \
     sh /tmp/k3s-install.sh
```

Optional flags, depending on your setup:

- `--docker` — use the Docker daemon as the container runtime. Dev convenience:
  images built locally with `docker build` are immediately visible to the
  cluster (no registry, no image import). Without it, k3s uses its embedded
  containerd and locally built images need `k3s ctr images import` or a
  registry.
- `--cluster-init` — embedded etcd instead of sqlite (needed only if you might
  later add nodes).
- `--kube-apiserver-arg=oidc-...` — wire the API server to your IdP if you want
  OIDC kubectl access.

Then point kubectl at the cluster:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes    # expect: 1 node, Ready, no taints
```

Note the kubeconfig context is named `default` on a stock k3s install — nothing
in setup.sh depends on the context or cluster name; it uses whatever
`KUBECONFIG`/current context points at.

Host prerequisites (the preflight per-node checks verify these):

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1 net.ipv4.ip_forward=1
```

### Wiping and reinstalling

k3s has no in-place "reset" — the supported wipe is uninstall + reinstall
(this also deletes all cluster data and PVs under
`/var/lib/rancher/k3s/storage`):

```bash
sudo /usr/local/bin/k3s-uninstall.sh
# then re-run the install command above
```

For tearing down only the NICo stack while keeping the cluster, use
[`clean.sh`](README.md#teardown) instead.

## MetalLB configuration (L2)

The committed `values/metallb-config.yaml` defaults to BGP with per-node TOR
peers — for a single dev box use **L2 mode** instead: comment out the
`BGPPeer`/`BGPAdvertisement` sections and uncomment `L2Advertisement`, then
give the pools a free IP range. The range does not need to be routed anywhere
for on-box use: kube-proxy makes LoadBalancer VIPs reachable from the node
itself, and L2/ARP announcement only matters for *other* hosts on the same
subnet.

## Running the install

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export NICO_IMAGE_REGISTRY=<registry>
export NICO_CORE_IMAGE_TAG=<tag>
export NICO_REST_IMAGE_TAG=<tag>
# export REGISTRY_PULL_SECRET=<key>   # not needed for locally built images

./setup.sh --single-node-k3s -y \
    --core-values /path/to/your-dev-core-values.yaml \
    --metallb-config /path/to/your-l2-metallb.yaml
```

Preflight can be run standalone with the same flag:

```bash
./preflight.sh --single-node-k3s
```

Verify afterwards with `helm-prereqs/health-check.sh`, and for simulated
hardware see the machine-a-tron docs
(`docs/development/machine-a-tron-deployment.md`) — its override/proxy-direct
mode needs no MetalLB or extra networking and runs fine on a single node.

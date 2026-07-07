# Launchpad — NICo deployment handoff

How to deploy the full NICo (carbide) + NICo REST stack to the **launchpad** GB300 NVL72 cluster,
reproducing what is currently running. This package contains the launchpad-specific config +
install scripts; the charts themselves live in the `infra-controller-core` repo
(`helm-prereqs/` and `helm/rest/`).

> ⚠️ **Secrets:** files here contain BMC credentials inline (`expected_machines.launchpad.json`,
> `PHASE4-nico.md`, `RUNBOOK.md`). This directory is **git-ignored on purpose** — hand it off by
> copying the folder, never by committing it.

> 🔁 **Sync note:** this is a mirror of `launchpad-bringup/`. When you change config here, make the
> same change in `launchpad-bringup/` (and vice-versa) so both stay identical.

---

## 0. What's running (target state)

| Layer | Helm release / namespace | Version |
|---|---|---|
| MetalLB (L2) | `metallb` / metallb-system | 0.14.5 |
| cert-manager | `cert-manager` / cert-manager | v1.17.1 |
| Vault | `vault` / vault | 1.14.0 |
| External Secrets | `external-secrets` / external-secrets | 0.14.3 |
| Postgres operator | `postgres-operator` / postgres | 1.10.1 |
| NICo prereqs | `nico-prereqs` / nico-system | 0.1.0 |
| **NICo Core** | `nico` / nico-system | image **`v2.0.0-pr-373-g8f81824c5`** |
| **NICo REST** | `nico-rest` (+ `nico-rest-site-agent`) / nico-rest | 1.6.0 |
| Temporal (self-hosted, for REST) | `temporal` / temporal | 1.22.6 |

- **Core image:** `nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:v2.0.0-pr-373-g8f81824c5`
  (upstream PR #2809 build — pure upstream deps, no forks).
- **REST image tag:** `v1.6.0`.

---

## 1. Prerequisites (do this first)

1. **Teleport / kube context** — everything below talks to the cluster through Teleport. Log in and
   select the launchpad kube cluster:
   ```bash
   tsh login --proxy=<your-teleport-proxy>
   tsh kube login rg-forge-launchpad
   kubectl config current-context     # must show ...-rg-forge-launchpad
   ```
   **All `kubectl`/`helm` commands must run against the `rg-forge-launchpad` context.** If you keep a
   raw kubeconfig instead, export it: `export KUBECONFIG=<path-to>/sites/launchpad/kubeconfig`.

2. **Repo** — clone `infra-controller-core` (the charts + installer live there). This `launchpad-deploy/`
   folder sits at the repo root next to `helm-prereqs/`.

3. **NGC pull secret** — you need the write-scoped NGC API key for `nvcr.io/0837451325059433/...`
   (ask the team / 1Password). Export it as `REGISTRY_PULL_SECRET`.

4. **Tools:** `kubectl`, `helm`, `helmfile`, `jq`, `cargo-make` not needed (images are prebuilt).

---

## 2. (Only for a brand-new cluster) nodes, IPs, Teleport

If the 3 site controllers are already up and Teleport-onboarded (they are, on launchpad), **skip to §3.**
For a fresh rack:
- `netplan/cp-{1,2,3}_00-installer-config.yaml` — static IPs (`172.16.2.11/12/13`, bond0, reboot-persistent).
- `teleport/install_teleport.sh` + `kube-agent-values.yaml` + `launchpad-token.yaml` — node SSH + kube-agent onboarding.
- `deployctl/cluster-spec.launchpad.yaml` — the kubespray cluster spec.

---

## 3. Deploy NICo infra + Core

The installer is `helm-prereqs/setup.sh` in the repo. It runs infra phases 1–5 (local-path,
postgres-operator, **MetalLB**, cert-manager, Vault, external-secrets, nico-prereqs) and then NICo
Core (phase 6). Run it with the launchpad value overlays from this folder:

```bash
cd <repo>/helm-prereqs
export KUBECONFIG=<launchpad kubeconfig>           # or rely on the tsh kube context
export NICO_IMAGE_REGISTRY=nvcr.io/0837451325059433/carbide-dev
export NICO_CORE_IMAGE_TAG=v2.0.0-pr-373-g8f81824c5
export REGISTRY_PULL_SECRET='<NGC API key>'

./setup.sh --skip-rest \
  --core-values   ../launchpad-deploy/nico/nico-core.launchpad.yaml \
  --metallb-config ../launchpad-deploy/nico/metallb-config.launchpad.yaml \
  -y
```

Notes / gotchas (learned the hard way):
- `setup.sh` is a **fresh-install** tool — it re-reconciles infra phases 1–5 every run. On an
  **already-installed** cluster a `helm upgrade` of MetalLB can hit a CRD server-side-apply
  conflict (`bgppeers.metallb.io … caBundle`). For a clean cluster it's fine; to *update only Core*
  on an existing cluster, prefer the targeted roll in §6 instead of re-running setup.sh.
- Verify after: `kubectl -n nico-system get pods` all Running; each service has its VIP
  (`172.16.2.40–.49`); `nslookup carbide-api.forge <unbound VIP .42>` resolves.

---

## 4. Deploy NICo REST (v1.6.0)

REST is **not** installed by `setup.sh --skip-rest`. Use the surgical script in this folder (it installs
the CA issuer, REST postgres, Keycloak dev IdP, Temporal + namespaces, the `nico-rest` umbrella, and the
site-agent — all confined to the `nico-rest` / `postgres` / `temporal` namespaces, never touching Core):

```bash
cd <repo>
export KUBECONFIG=<launchpad kubeconfig>
export REGISTRY_PULL_SECRET='<NGC API key>'         # same NGC key
./launchpad-deploy/install-rest-1.6.0.sh
```
The script pins: registry `nvcr.io/0837451325059433/carbide-dev`, REST tag `v1.6.0`, and a **stable
site UUID `7f91b08b-140b-4578-9515-0b1962764ab1`** (keep it constant on re-runs).

### Two site-agent gotchas (both fixed in this package — read if pods crashloop)

**1. Cert mount path (the crashloop root cause — already fixed in the chart here).**
The v1.6.0 `nico-rest-site-agent` chart mounted the Core-gRPC client cert secret (`nico-certs`) at
`/etc/nico`, but the binary reads it from **`/etc/core-grpc/`** (no env override exists). With the cert
missing, `CreateGrpcClient` retried forever and the retry path re-registered Prometheus collectors →
`panic: duplicate metrics collector registration` (`coregrpc/metrics.go:49`) → permanent CrashLoopBackOff.
**Fix (committed in `helm/rest/nico-rest-site-agent/templates/statefulset.yaml`):** mount `nico-certs` at
`/etc/core-grpc`. To patch a live cluster without re-installing:
```bash
kubectl -n nico-rest patch statefulset nico-rest-site-agent --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/volumeMounts/1/mountPath","value":"/etc/core-grpc"}]'
kubectl -n nico-rest delete pod -l app.kubernetes.io/name=nico-rest-site-agent
```
> Residual: there is a latent v1.6.0 bug where the cert-reload watcher re-calls `makeGrpcClientMetrics()`
> on first cert-volume settle, causing **one** panic/restart per pod at startup; pods then run stably.
> Harmless (1 restart, self-heals). A real fix needs a site-agent image rebuild.

**2. Expired bootstrap OTP (`bad status code: 500` / empty temporal certs).**
The site-agent uses a one-time passcode (OTP) from the `site-registration` secret to download its Temporal
client cert from `site-manager`. The OTP expires (default ~24h). If the site sits un-bootstrapped past
that, you'll see site-manager log `Expired OTP received`, the agent loop `bad status code: 500`, and
`temporal-client-site-agent-certs` stays empty (→ `tls: failed to find any PEM data`). **Fix — roll a
fresh OTP and re-sync it:**
```bash
SITE=7f91b08b-140b-4578-9515-0b1962764ab1
# 1. mint a fresh OTP server-side (resets the Site CR to AwaitHandshake):
kubectl -n nico-rest run smroll --rm -i --restart=Never --image=alpine/k8s:1.29.4 --command -- \
  sh -c "curl -sS -k -X POST https://nico-rest-site-manager.nico-rest:8100/v1/site/roll/${SITE}"
# 2. copy the new OTP from the Site CR into the site-registration secret (preserve cacert/creds-url):
NEWOTP=$(kubectl -n nico-rest get site site-${SITE} -o jsonpath='{.status.otp.passcode}')
CA=$(kubectl -n nico-rest get secret site-registration -o jsonpath='{.data.cacert}' | base64 -d)
URL=$(kubectl -n nico-rest get secret site-registration -o jsonpath='{.data.creds-url}' | base64 -d)
kubectl -n nico-rest delete secret site-registration --ignore-not-found
kubectl -n nico-rest create secret generic site-registration \
  --from-literal=site-uuid="${SITE}" --from-literal=otp="${NEWOTP}" \
  --from-literal=creds-url="${URL}" --from-literal=cacert="${CA}"
# 3. restart the agent; it completes the handshake → CR goes HandshakeComplete, temporal certs populate:
kubectl -n nico-rest rollout restart statefulset/nico-rest-site-agent
```
A **fresh** install never hits this — the bootstrap Job mints a just-in-time OTP. It only bites a site
that was deployed but left un-handshaked for >OTP-TTL. The site-agent is the REST/cloud bridge; this does
**not** block carbide host ingestion either way.

---

## 5. ⚠️ DHCP safety — the #1 operational rule on this cluster

There is a **self-hosted ISC `dhcrelay` running on cp-1** (`launchpad-control-plane-1`, bond0,
giaddr `172.16.2.11`) that forwards BMC DHCP to the kea VIP `172.16.2.41`. **If the `nico-dhcp` (kea)
pod ever lands on cp-1, the relay goes deaf and the whole rack loses DHCP** (this caused a real outage).

**Immediately after Core is up, pin `nico-dhcp` off cp-1** (persistent guard):
```bash
kubectl -n nico-system patch deploy nico-dhcp --type=merge -p '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"kubernetes.io/hostname","operator":"NotIn","values":["launchpad-control-plane-1"]}]}]}}}}}}}'
```
And **any time you roll/restart workloads, cordon cp-1 first** as a backup, then uncordon after:
```bash
kubectl cordon launchpad-control-plane-1
# ... roll ...
kubectl -n nico-system get pod -l app.kubernetes.io/name=nico-dhcp -o wide   # confirm node ≠ cp-1
kubectl uncordon launchpad-control-plane-1
```
(See `DHCP-RELAY.md` for the full relay design and `RUNBOOK.md` for recovery steps.)

---

## 6. Updating just the carbide image on an existing cluster (DHCP-safe)

To roll a new Core image without re-running setup.sh (this is how `v2.0.0-pr-373` was deployed):

```bash
T=nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:<new-tag>
# 1. migrate the DB first (one-off Job from the existing migrate job, new image):
kubectl -n nico-system get job nico-api-migrate -o json \
 | jq --arg img "$T" 'del(.spec.selector,.spec.template.metadata.labels,.status,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.ownerReferences,.metadata.labels) | .metadata.name="nico-api-migrate-new" | .spec.template.spec.containers[0].image=$img' \
 | kubectl apply -f -
kubectl -n nico-system wait --for=condition=complete job/nico-api-migrate-new --timeout=180s
# 2. cordon cp-1, roll all carbide workloads, verify dhcp off cp-1, uncordon:
kubectl cordon launchpad-control-plane-1
for d in nico-api nico-pxe nico-hardware-health; do kubectl -n nico-system set image deploy/$d $d=$T; done
kubectl -n nico-system set image deploy/nico-ssh-console-rs ssh-console-rs=$T
kubectl -n nico-system set image statefulset/nico-dns nico-dns=$T
kubectl -n nico-system set image deploy/nico-dhcp nico-dhcp=$T
kubectl -n nico-system rollout status deploy/nico-api --timeout=180s
kubectl -n nico-system get pod -l app.kubernetes.io/name=nico-dhcp -o wide   # node ≠ cp-1
kubectl uncordon launchpad-control-plane-1
```
**Always migrate before rolling** — a newer image expecting columns the DB lacks will spam
`ColumnNotFound` (this happened with pr-340).

---

## 7. Expected-machines + ingestion settings

Seed the 18 GB300 trays and their per-host settings (`expected-machine` is the gate — only listed BMC
MACs are ingested):
```bash
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"
# load the 18 trays from JSON:
$AC expected-machine replace-all ./nico/expected_machines.launchpad.json   # path inside admincli pod / or add one-by-one
```
Per-host knobs (see `CONFIG-GUIDE.md` for the full matrix):
- `--dpu-mode dpu-mode|nic-mode|no-dpu` (default dpu-mode), `--dpf-enabled false` (DPF is **not** deployed here).
- The **admin network was widened `172.16.4.0/29 → /24`** in siteConfig so dpu-mode hosts can allocate
  admin IPs for all 18 (see `CONFIG-GUIDE.md`).

Hardware prerequisites for dpu-mode (NOT done by NICo):
- After a NIC→DPU mode switch, run **`mlxfwreset -d /dev/mst/mt41692_pciconf0 -l 4 r`** per tray to apply it.
- Power on any DPU BMCs that are off (they must be reachable for dpu-mode hosts to ingest).

---

## 8. Verify
```bash
kubectl -n nico-system get pods,svc           # all Running; VIPs .40–.49 assigned
kubectl -n nico-rest get pods                 # all Running except the known site-agent crashloop
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli machine show
```

See **`CONFIG-GUIDE.md`** for changing the carbide siteConfig TOML, network prefixes, image tags, and
per-host settings. See **`NETWORKING.md`** for the full network design and **`ADMIN-CLI.md`** for the
operator CLI.

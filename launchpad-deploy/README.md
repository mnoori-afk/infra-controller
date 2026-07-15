# Launchpad — NICo deployment handoff

How to deploy the full NICo (carbide) stack — **Core + REST + Flow + RMS + rack config + ssh-console** —
to the **launchpad** GB300 NVL72 cluster (`rg-forge-launchpad`), reproducing what is currently running.
This folder holds the launchpad-specific config + install scripts; the charts themselves live in the
`infra-controller-core` repo (`helm-prereqs/`, `helm/`, `helm/rest/`).

> 📦 **This folder is the git-tracked deploy source-of-truth.** It lives on branch **`launchpad-deployment`**
> (kept to a single commit on top of `origin/main`). `launchpad-bringup/` is the *gitignored* live-truth
> working copy — when the two drift, **live is correct**; reconcile this folder to match live.
>
> 🔐 **Secrets:** everything here is safe to commit **except** `nico/expected_machines.launchpad.json`
> (rendered with a cleartext BMC password) — that one file is gitignored via `launchpad-deploy/.gitignore`.
> All other credentials come from **Vault** (see `VAULT-CREDS.md`); config references them, never inlines them.

> 🧭 **Prepping a new, similar site?** Follow the deploy order in §0.1 top-to-bottom. Every layer has a
> dedicated doc; this README is the index + the Core/REST steps. The only truly site-specific inputs are:
> the 3 control-plane node IPs/netplan, the MetalLB VIP pool, the site domain, the FNN/EVPN route-targets
> (from the network team), the expected-machine BMC list, and a fresh REST site UUID.

---

## 0. What's running (target state, 2026-07-08)

| Layer | Helm release / namespace | Version / image |
|---|---|---|
| Helm CLI | — | **v4.1.3** (Helm 4 — SSA, `--force-conflicts`, `--take-ownership`) |
| MetalLB (L2) | `metallb` / metallb-system | 0.14.5 |
| cert-manager | `cert-manager` / cert-manager | v1.17.1 |
| Vault | `vault` / vault | 1.14.0 |
| External Secrets | `external-secrets` / external-secrets | 0.14.3 |
| Postgres operator | `postgres-operator` / postgres | 1.10.1 |
| NICo prereqs | `nico-prereqs` / nico-system | 0.1.0 |
| **NICo Core** | `nico` / nico-system (chart nico-0.1.1, **helm rev 19**) | **`nvmetal-carbide:v2.0.0-pr-503-g49a48a69d`** |
| Boot artifacts (PXE) | init container in `nico-pxe` | `boot-artifacts-aarch64:v2.0.0-pr-503-g49a48a69d` |
| **NICo REST** (+ site-agent) | `nico-rest` / nico-rest | **`v2.1.0-pr-14-g0d5452b9a`** |
| **NICo Flow** (flow/psm/nsm) | `flow` / flow | **`v2.1.0-pr-14-g0d5452b9a`** |
| Temporal (self-hosted, for REST/Flow) | `temporal` / temporal | 1.22.6 |
| REST/Temporal Postgres | `postgres` statefulset / postgres | postgres:14.4-alpine, **4Gi/2cpu** (see §11) |
| **RMS** (Rack Manager Service) | `rms-api-server` / rack-manager | see `RMS-RUNBOOK.md` (verify live image) |

- **Core image:** `nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:v2.0.0-pr-503-g49a48a69d`.
- **REST/Flow image:** `nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:v2.1.0-pr-14-g0d5452b9a`
  (REST + Flow ship on the same image line).
- **REST site UUID:** `8c894583-bea4-445d-a5bd-46ee0e3cb3fb` (org `ncx`), site **Registered / isOnline:true**.
  > The old UUID `7f91b08b-…` is **orphaned** — do not use it.

### 0.1 Deploy order (do it in this sequence)

| # | Layer | How | Doc |
|---|---|---|---|
| 1 | Infra + **NICo Core** | `helm-prereqs/setup.sh --skip-rest` + launchpad overlays (§3) | `nico/PHASE4-nico.md`, `CONFIG-GUIDE.md` |
| 2 | **NICo REST** (v2.1) | `install-rest-1.6.0.sh` (§4) | this README §4 |
| 3 | **Register the REST site** | `nico/register-rest-site.sh` (§4b) | this README §4b |
| 4 | **NICo Flow** + agent↔Flow | `nico/deploy-flow.sh` (§5) | `FLOW-FIXES.md` |
| 5 | **RMS** (rack-manager) | helm (§6) | `RMS-ENABLEMENT.md`, `RMS-RUNBOOK.md` |
| 6 | **Rack + component-manager** siteConfig | edit CM + rollout nico-api (§7) | `nico/RACK-CONFIG.md` |
| 7 | **ssh-console-rs** cert console | config + rollout restart (§8) | `SSH-CONSOLE.md` |
| — | Expected-machines + ingestion | admin-cli seed (§9) | `CONFIG-GUIDE.md`, `ADMIN-CLI.md` |

---

## 1. Prerequisites (do this first)

1. **Helm 4** (`v4.1.3+`). Several steps rely on server-side apply and `--force-conflicts` /
   `--take-ownership` (see §12). `helm version --short` must report `v4.x`.

2. **Teleport / kube context** — everything talks to the cluster through Teleport:
   ```bash
   tsh login --proxy=<your-teleport-proxy>
   tsh kube login rg-forge-launchpad
   kubectl config current-context     # must show ...-rg-forge-launchpad
   ```
   **All `kubectl`/`helm` commands must run against the `rg-forge-launchpad` context.**
   > ⚠️ If you switch to another site's context (demo1, ytl, …), STOP running cluster commands here
   > until you switch back — it is easy to apply launchpad config to the wrong cluster.

3. **Repo** — clone `infra-controller-core`. This `launchpad-deploy/` folder sits at the repo root.

4. **NGC pull secret** — the write-scoped NGC API key for `nvcr.io/0837451325059433/...`
   (ask the team / 1Password). Export as `REGISTRY_PULL_SECRET`.

5. **Tools:** `kubectl`, `helm` (v4), `jq`, `base64`. `tsh` for tunneling to internal VIPs (§8).

---

## 2. (Only for a brand-new cluster) nodes, IPs, Teleport

If the 3 site controllers are already up and Teleport-onboarded (they are, on launchpad), **skip to §3.**
For a fresh rack:
- `netplan/cp-{1,2,3}_00-installer-config.yaml` — static IPs (`172.16.2.11/12/13`, bond0, reboot-persistent).
- `teleport/install_teleport.sh` + `kube-agent-values.yaml` + `launchpad-token.yaml` — node SSH + kube-agent onboarding.
- `deployctl/cluster-spec.launchpad.yaml` — the kubespray cluster spec (k8s v1.30.4, Calico, ipvs).
- See `RUNBOOK.md` for the full node/substrate bring-up record and `NETWORKING.md` for the network design.

---

## 3. Deploy NICo infra + Core

`helm-prereqs/setup.sh` runs infra phases 1–5 (local-path, postgres-operator, **MetalLB**, cert-manager,
Vault, external-secrets, nico-prereqs) then NICo Core (phase 6). Run it with the launchpad overlays:

```bash
cd <repo>/helm-prereqs
export KUBECONFIG=<launchpad kubeconfig>           # or rely on the tsh kube context
export NICO_IMAGE_REGISTRY=nvcr.io/0837451325059433/carbide-dev
export NICO_CORE_IMAGE_TAG=v2.0.0-pr-503-g49a48a69d
export REGISTRY_PULL_SECRET='<NGC API key>'

./setup.sh --skip-rest \
  --core-values   ../launchpad-deploy/nico/nico-core.launchpad.yaml \
  --metallb-config ../launchpad-deploy/nico/metallb-config.launchpad.yaml \
  -y
```

Notes / gotchas (learned the hard way):
- `setup.sh` is a **fresh-install** tool — it re-reconciles infra phases 1–5 every run. On an
  **already-installed** cluster a `helm upgrade` of MetalLB can hit a CRD server-side-apply conflict
  (`bgppeers.metallb.io … caBundle`). For a clean cluster it's fine; to *update only Core* on an existing
  cluster, prefer the targeted roll in §10 (or the full `helm upgrade` in §12) instead of re-running setup.sh.
- `nico/nico-core.launchpad.yaml` is the Core siteConfig — it carries the full network (FNN/EVPN, VNI,
  VIPs, `deny_prefixes = []`), the rack/component-manager/RMS blocks (§7), and the ssh-console-rs config
  (§8). Do **not** hand-edit the live CM without also updating this file (live is source-of-truth on drift).
- Verify after: `kubectl -n nico-system get pods` all Running; each service has its VIP
  (`172.16.2.40–.49`, see `NETWORKING.md`); `nslookup carbide-api.forge <unbound VIP .42>` resolves.

---

## 4. Deploy NICo REST (v2.1)

REST is **not** installed by `setup.sh --skip-rest`. Use the surgical script in this folder (it installs the
CA issuer, REST postgres, Keycloak dev IdP, Temporal + namespaces, the `nico-rest` umbrella, and the
site-agent — confined to the `nico-rest` / `postgres` / `temporal` namespaces, never touching Core):

```bash
cd <repo>
export KUBECONFIG=<launchpad kubeconfig>
export REGISTRY_PULL_SECRET='<NGC API key>'         # same NGC key
./launchpad-deploy/install-rest-1.6.0.sh
```
> The filename says `1.6.0` for legacy reasons — the script is **pinned to REST tag
> `v2.1.0-pr-14-g0d5452b9a`** and the stable site UUID **`8c894583-bea4-445d-a5bd-46ee0e3cb3fb`**.
> The v1.6→v2.1 bump is what fixed the site-agent `duplicate metrics collector` panic that blocked
> agent↔Flow (see `nico/V2-UPGRADE-PLAN.md`, historical).

### Site-agent gotcha — expired bootstrap OTP (`bad status code: 500` / empty temporal certs)

The site-agent uses a one-time passcode from the `site-registration` secret to download its Temporal client
cert from `site-manager`. The OTP expires (~24h). If the site sits un-bootstrapped past that: site-manager
logs `Expired OTP received`, the agent loops `bad status code: 500`, and `temporal-client-site-agent-certs`
stays empty (→ `tls: failed to find any PEM data`). **Fix — roll a fresh OTP and re-sync it:**
```bash
SITE=8c894583-bea4-445d-a5bd-46ee0e3cb3fb
kubectl -n nico-rest run smroll --rm -i --restart=Never --image=alpine/k8s:1.29.4 --command -- \
  sh -c "curl -sS -k -X POST https://nico-rest-site-manager.nico-rest:8100/v1/site/roll/${SITE}"
NEWOTP=$(kubectl -n nico-rest get site site-${SITE} -o jsonpath='{.status.otp.passcode}')
CA=$(kubectl -n nico-rest get secret site-registration -o jsonpath='{.data.cacert}' | base64 -d)
URL=$(kubectl -n nico-rest get secret site-registration -o jsonpath='{.data.creds-url}' | base64 -d)
kubectl -n nico-rest delete secret site-registration --ignore-not-found
kubectl -n nico-rest create secret generic site-registration \
  --from-literal=site-uuid="${SITE}" --from-literal=otp="${NEWOTP}" \
  --from-literal=creds-url="${URL}" --from-literal=cacert="${CA}"
kubectl -n nico-rest rollout restart statefulset/nico-rest-site-agent
```
A **fresh** install never hits this — the bootstrap Job mints a just-in-time OTP. It only bites a site left
un-handshaked for >OTP-TTL. The site-agent is the REST/cloud bridge; this does **not** block carbide host ingestion.

> ⚠️ A `helm upgrade` of the site-agent wipes `temporal-client-site-agent-certs` back to an empty placeholder
> (despite the `resource-policy: keep` annotation), consuming the OTP — after any site-agent upgrade, roll the
> OTP as above.

---

## 4b. Register the REST site

So `GET /v2/org/ncx/nico/site` returns the site and the agent can pair. Automated in
`nico/register-rest-site.sh` (mints a Keycloak ProviderAdmin token via `helm-prereqs/keycloak/get-token.sh`,
`POST`s the v2 `/site`, then re-points the agent):
```bash
./launchpad-deploy/nico/register-rest-site.sh
# result: site 8c894583-… Registered, isOnline:true
```
See `nico/V2-UPGRADE-PLAN.md` for the token/registration details.

---

## 5. Deploy NICo Flow (+ enable agent↔Flow)

```bash
ENABLE_AGENT_FLOW=true ./launchpad-deploy/nico/deploy-flow.sh
```
This creates the Temporal `flow` namespace + an image-pull-secret in ns `flow`, installs `nico-flow/psm/nsm`
at `v2.1.0-pr-14-g0d5452b9a`, and flips the site-agent `FLOW_GRPC_ENABLED=true`. The DB creds + vault tokens
are already synced by nico-prereqs (`flow.enabled=true`). See **`FLOW-FIXES.md`** for the two gotchas that
matter (empty-`auths` image-pull-secret clobber; the shared **Temporal Postgres sizing** fix in §11 that
actually unblocked site pairing).

---

## 6. Deploy RMS (rack-manager)

NICo Core is already configured (siteConfig `[rms]`, §7) to call `rms-api-server.rack-manager.svc:8801` over
mTLS, but RMS is a **separate** deployment. Full steps in **`RMS-ENABLEMENT.md`** + **`RMS-RUNBOOK.md`**.
mTLS uses the `vault-nico-issuer` SPIFFE certs (nico-api's `/var/run/secrets/spiffe.io` ↔ RMS `--tls-ca`).
Verify: `rms-api-server` logs `BatchGetPowerState status=200 peer="CN=nico-api…" rack=launchpad-r1`.

---

## 7. Rack + component-manager siteConfig

The `[site_explorer]`, `[rack_profiles.NVL72_GB300]`, `[component_manager]`, and `[rms]` (HTTPS + mTLS)
blocks are already in `nico/nico-core.launchpad.yaml`. To (re)apply on a live cluster and roll nico-api, see
**`nico/RACK-CONFIG.md`** (what to apply + how it diverges from the shared reference). Rack `launchpad-r1`
should reach state `Created`. A failing MV test is disabled here: `tests=[{id="forge_DcgmFullLong",enable=false}]`.

---

## 8. ssh-console-rs (SSH serial console)

Cert-based admin serial console (SOL) to hosts/BMCs, VIP `172.16.2.49`. Config lives in
`nico/nico-core.launchpad.yaml` under `nico-ssh-console-rs.configFiles.config`. **Full playbook +
gotchas in `SSH-CONSOLE.md`.** The one that will bite you: the chart has **no config-checksum**, so after
any config change you **must** `kubectl -n nico-system rollout restart deploy/nico-ssh-console-rs` — a CM
update / `helm upgrade` alone will not restart the pod (stale-pod symptom: `openssh certificate CA
certificate not trusted`). Login username = the **target machine_id**, not your name; reach the VIP via a tunnel.

---

## 9. Expected-machines + ingestion settings

Seed the 18 GB300 trays and their per-host settings (`expected-machine` is the gate — only listed BMC MACs
are ingested):
```bash
AC="kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli"
$AC expected-machine replace-all ./nico/expected_machines.launchpad.json
```
Per-host knobs (see `CONFIG-GUIDE.md` for the full matrix): `--dpu-mode dpu-mode|nic-mode|no-dpu`,
`--dpf-enabled false` (DPF is not deployed here). Hardware prereqs for dpu-mode (NOT done by NICo):
after a NIC→DPU switch run `mlxfwreset -d /dev/mst/mt41692_pciconf0 -l 4 r` per tray; power on any off DPU BMCs.

---

## 10. Updating just the carbide image on an existing cluster (DHCP-safe)

To roll a new Core image without re-running setup.sh:
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
**Always migrate before rolling** — a newer image expecting columns the DB lacks will spam `ColumnNotFound`.

---

## 11. ⚠️ Two standing operational rules

### 11a. DHCP safety — the #1 rule on this cluster
A **self-hosted ISC `dhcrelay` runs on cp-1** (`launchpad-control-plane-1`, bond0, giaddr `172.16.2.11`)
forwarding BMC DHCP to the kea VIP `172.16.2.41`. **If the `nico-dhcp` (kea) pod ever lands on cp-1, the
relay goes deaf and the whole rack loses DHCP** (caused a real outage). Pin `nico-dhcp` off cp-1 right after
Core is up, and cordon cp-1 before any roll:
```bash
kubectl -n nico-system patch deploy nico-dhcp --type=merge -p '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"kubernetes.io/hostname","operator":"NotIn","values":["launchpad-control-plane-1"]}]}]}}}}}}}'
```
(Full relay design in `DHCP-RELAY.md`; recovery in `RUNBOOK.md`.)

### 11b. Temporal Postgres sizing — the site-pairing unblocker
The single `postgres-0` (ns `postgres`, alpine statefulset) hosts Temporal's `temporal` + `temporal_visibility`
DBs plus `nico` + `keycloak`. At the default 512Mi it starved: Temporal `ReadHistoryBranch` reads exceeded
deadline → `pq: canceling statement due to user request` → workflows stalled → **the site would not pair**.
It is bumped to **requests 2Gi/1cpu, limits 4Gi/2cpu** (`rest-api/deploy/kustomize/base/postgres/statefulset.yaml`).
Keep this on any new site. Worker CPU bumps did NOT help — the DB was the bottleneck.

---

## 12. Healing a stuck `nico` helm release (Helm 4 `--force-conflicts`)

Symptom: `helm upgrade nico` fails with `conflict … nico-api-site-config-files … conflicts with "kubectl-edit"`.
Cause: a prior `kubectl edit` took server-side-apply field ownership of a CM, so Helm's SSA collides. This is
exactly what happened on launchpad (revs 15–18 failed) and was healed to rev 19 with:
```bash
CTX=nv-stg-dgxc.teleport.sh-rg-forge-launchpad
helm --kube-context "$CTX" upgrade nico ./helm -n nico-system \
  -f launchpad-deploy/nico/nico-core.launchpad.yaml \
  --set global.image.repository=nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide \
  --set global.image.tag=v2.0.0-pr-503-g49a48a69d \
  --force-conflicts --timeout 10m
```
Before healing, **diff the render vs live** (services' `externalTrafficPolicy`, images, nico-pxe pod spec)
so the upgrade doesn't silently revert a live hand-edit — on launchpad the only delta was a `deny_prefixes`
comment (nico-api has no config-reloader, so it didn't even restart). If you hit `invalid ownership metadata`
instead of field conflicts, add `--take-ownership`.

---

## 13. Verify
```bash
kubectl -n nico-system get pods,svc           # all Running; VIPs .40–.49 assigned
kubectl -n nico-rest  get pods                 # REST + site-agent Running
kubectl -n flow       get pods                 # nico-flow/psm/nsm Running
kubectl -n rack-manager get pods               # rms-api-server Running
kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli machine show
helm -n nico-system list                       # nico STATUS deployed
```

---

## See also
- `CONFIG-GUIDE.md` — changing the carbide siteConfig TOML, network prefixes, image tags, per-host settings.
- `NETWORKING.md` — full network design + VIP map.  `DHCP-RELAY.md` — the self-hosted relay.
- `SSH-CONSOLE.md` — ssh-console-rs cert console.  `FLOW-FIXES.md` — Flow enablement.
- `RMS-ENABLEMENT.md` / `RMS-RUNBOOK.md` — RMS.  `nico/RACK-CONFIG.md` — rack/component-manager config.
- `observability/README.md` — local Loki + OTEL collectors + Grafana/Prometheus (log/metric collection, no Panoptes).
- `VAULT-CREDS.md` — Vault BMC/UEFI creds.  `ADMIN-CLI.md` — operator CLI.
- `WORKLOG-2026-07-02.md`, `WORKLOG-2026-07-08.md` — dated work logs.

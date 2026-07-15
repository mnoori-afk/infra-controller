# Launchpad local observability — Loki + OTEL + Grafana + Prometheus (no Panoptes)

Stands up a **self-contained, local** logging/metrics stack on the launchpad site. All logs land in a
**local Loki** — nothing is pushed to Panoptes. Mirrors how `forged` does OTEL+Loki, minus Panoptes/Kratos,
packaged as Helm (launchpad is 100% Helm, not kustomize/ArgoCD).

## What it collects
| Source | Path | How |
|---|---|---|
| All k8s pod stdout (nico-*, nico-rest, flow, temporal, rack-manager, … + CP static pods) | `/var/log/pods/*` | **agent** DaemonSet → Loki (org `forge`) |
| Node host units — cp-1 `isc-dhcp-relay` (systemd, not a pod) + kubelet/containerd | journald | **DEFERRED** — the `otel-collector-contrib` image has no `journalctl`, so the `journald` receiver crashes. Re-add later with a journald-capable image/sidecar. Pod logs cover everything else. |
| ssh-console serial transcripts | `/var/log/consoles/*` | existing `nico-ssh-console-rs` **sidecar** → Loki (org `nico`) |
| DPU (BlueField) DOCA/HBN/kernel/auth logs + host metrics | DPU node | `bluefield/charts/nico-otelcol` → **gateway** OTLP/mTLS → Loki + Prometheus |

## Relationship to forged's `opentelemetry-collector-v2` (what prod sites run)

This bundle **follows forged v2** (`bases/argocd/apps/opentelemetry-collector-v2` +
`overlays/opentelemetry-collector-config/remote_values.yaml`), minus Panoptes/Kratos. Same on the
load-bearing points: collector **chart/image 0.106.1**, the **`loki` exporter → `/loki/api/v1/push`**
(v2 has **not** moved to `otlphttp`/OTLP-to-Loki — so we keep the 0.106 image ceiling and don't switch),
`loki.resource.labels` + `loki.format: raw`, and **`forge_site` via `resource/site-label-loki` reading
`${env:OTEL_SITE_NAME}`** (set `OTEL_SITE_NAME` — the only per-site change for nvcert). Loki is the same
chart 5.15.0 / 2.8.4.

**Intentional divergences (all justified):**
- **DPU mTLS front-door.** Prod v2 fronts the OTLP receiver with a **Contour `HTTPProxy`** (mTLS terminated
  at Contour, `clientValidation.caSecret: otel/forge-roots`, 443→4317). **Launchpad has no Contour**
  (verified: no namespace/CRD), so we terminate the *same* mTLS **in the collector** behind a MetalLB
  LoadBalancer VIP (`.30:443` → `4317`), presenting a `site-issuer` cert (leaf signed by `site-root`) and
  validating the DPU client cert against `site-root`. Functionally equivalent, launchpad-native.
- **agent + gateway split** instead of v2's single daemonset — because without Contour the mTLS receiver
  wants one owner for the cert + VIP. The filelog/journald agent stays cert-free on every node.
- **+ journald receiver** for the cp-1 `isc-dhcp-relay` (v2 is filelog-only and would miss it).
- **+ Loki compactor `working_directory`/`shared_store`** (forged's Loki values omit these → its retention
  silently no-ops; ours actually enforces 360h).
- **− Panoptes/Kratos/logzio/oauth2** exporters and the `routing/otlp-logs` connector (the whole point).

## Components (upstream charts, same as forged)
| Release | ns | Chart | Notes |
|---|---|---|---|
| `loki` | `loki` | grafana/loki 5.15.0 | single-binary, `local-path-persistent` 50Gi, 360h retention. Service `loki:3100` (matches the pre-wired nico endpoints) |
| `otel-agent` | `otel` | open-telemetry/opentelemetry-collector | DaemonSet, filelog → Loki. Cert-free |
| `otel-collector-gateway` | `otel` | open-telemetry/opentelemetry-collector | Deployment, OTLP/mTLS receiver on VIP `otel-receiver.forge:443` |
| `obs` | `monitoring` | prometheus-community/kube-prometheus-stack 59.1.0 | Prometheus + Grafana (Loki + Prometheus datasources) |

> **Image pin:** the collector `loki` exporter is contrib-only and deprecated. The values pin
> `otel/opentelemetry-collector-contrib:0.106.1` to match forged v2. If you ever bump it, confirm the
> `loki` exporter still ships at that tag (it is removed in a later release) or switch to Loki's native
> OTLP endpoint (`otlphttp` → `:3100/otlp`, which needs a newer Loki than the 2.8.4 that v2/this bundle use).

## Deploy (runbook)

Prereqs: on the launchpad kube context (`kubectl config current-context` ends `…rg-forge-launchpad`),
Helm v4, cert-manager + the `site-issuer`/`site-root` site CA present (they are).
Charts pull anonymously (no pull secret). The script creates ns `loki`/`otel`/`monitoring`. Run from
`<repo>/launchpad-deploy/observability`. `CTX=nv-stg-dgxc.teleport.sh-rg-forge-launchpad`.

**1. Apply the MetalLB VIP range** — must precede the LB services or Grafana/gateway stay `<pending>`. The
`172.16.2.30-.39` range is in `../nico/metallb-config.launchpad.yaml`:
```bash
kubectl --context "$CTX" apply -f ../nico/metallb-config.launchpad.yaml   # add --server-side --force-conflicts if SSA complains
kubectl --context "$CTX" -n metallb-system get ipaddresspool vip-pool-internal -o jsonpath='{.spec.addresses}{"\n"}'  # shows .30-.39
```

**2. Deploy Loki + agent + Prometheus/Grafana** (phases 1–5 of the script; no certs, no DPU):
```bash
./deploy-observability.sh
kubectl --context "$CTX" -n loki get pods; kubectl --context "$CTX" -n otel get pods; kubectl --context "$CTX" -n monitoring get pods
```
> **No auth anywhere:** Grafana is anonymous-Admin with the login form disabled; Loki (`auth_enabled:false`)
> and the collectors have no auth. This is an internal-only site reached by VIP/tunnel.
> The kube-prometheus-stack install is the slow one (CRDs + operator + Prometheus StatefulSet). If a
> `helm --wait` step exceeds your shell timeout, it keeps going server-side — re-check with `helm -n <ns> list`
> and `kubectl get pods`; re-running the script is idempotent (`upgrade --install`).

**3. Verify logs flow** (before DPU/DNS):
```bash
kubectl --context "$CTX" -n monitoring port-forward svc/obs-grafana 3000:80   # then http://localhost:3000
```
In Grafana → Explore → Loki datasource: `{forge_site="launchpad"}`, `{k8s_namespace_name="nico-system"}`,
`{component="host-journald"}` (grep for `isc-dhcp-relay`). Grafana is also at the VIP `172.16.2.31`.

**4. DNS records** — for humans to hit `grafana.forge` and (required) for the DPU to resolve
`otel-receiver.forge`. Records are in `../nico/nico-core.launchpad.yaml` unbound `localData`
(`otel-receiver.forge → .30`, `grafana.forge → .31`); apply via a Core `helm upgrade` (see `../README.md` §12):
```bash
helm --kube-context "$CTX" upgrade nico ./helm -n nico-system -f ../nico/nico-core.launchpad.yaml \
  --set global.image.repository=nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide \
  --set global.image.tag=v2.0.0-pr-503-g49a48a69d --force-conflicts
```

**5. DPU logs (gated on the mTLS check below):**
```bash
WITH_DPU=true ./deploy-observability.sh
```
DPU logs flow once `otel-receiver.forge` resolves (step 4) **and** the CA fingerprint matches.

**6. ssh-console transcripts:** flip `lokiLogCollector.enabled: true` in `../nico/nico-core.launchpad.yaml`,
Core `helm upgrade` (as step 4), then `kubectl -n nico-system rollout restart deploy/nico-ssh-console-rs`.

## Enabling the two existing collectors
- **ssh-console sidecar** (`../nico/nico-core.launchpad.yaml`, `nico-ssh-console-rs:` block): flip
  `lokiLogCollector.enabled: true` (image already pinned there), `helm upgrade` nico-core, then
  `kubectl -n nico-system rollout restart deploy/nico-ssh-console-rs` (the no-checksum gotcha —
  `../SSH-CONSOLE.md` §3). It ships straight to Loki over HTTP; only needs Loki up.
- **DPU** (`bluefield/charts/nico-otelcol`): DPF-deployed onto BlueField nodes, already pointed at
  `otel-receiver.forge:443`. No chart change — it just needs the VIP/DNS + the gateway's correctly-issued cert.

## DPU mTLS trust chain (the load-bearing bit) — ✅ WORKING as of 2026-07-15
The DPU otelcol trusts **`CN=site-root`** and presents a client cert also signed by site-root. VERIFIED live
on DPU `172.16.2.76`: `/etc/otelcol-contrib/certs/ca.pem` = self-signed **`site-root`** (SHA256
`31:9A:1F:…:F8:3E`); `otel-cert.pem` issuer = `CN=site-root`. So the gateway server cert
(`otel-receiver-certificate.yaml`) is issued by **`site-issuer`** (a ca-issuer backed by `site-root`, so the
leaf is signed *directly* by site-root), and the OTLP `client_ca_file` is that same secret's **`ca.crt`
(= site-root)** — no separate CA copy needed. 16 DPUs stream `hbn`/`dpu-auth-filelog`/`forge-dpu-agent`
logs + `transceiver_*` metrics through this. **No DPU changes were made** — the DPU otelcol runs
independently (forge-dpu provisioning, not NICo `dpf.enabled`); we only had to present a cert it trusts.
> Earlier this used `nico-rest-ca-issuer` ("NICo Local Dev CA") — a DIFFERENT CA the DPU does NOT trust →
> caused `x509: certificate signed by unknown authority`. Confirm on a DPU (read-only):
> `openssl x509 -in /etc/otelcol-contrib/certs/ca.pem -noout -issuer -fingerprint -sha256` → `CN=site-root`.
If they differ, repoint `otel-receiver-certificate.yaml`'s `issuerRef` at the matching issuer. Fallback:
run TLS-only (drop `client_ca_file`) or skip DPU — phases 1–4 have no cert dependency.

## Verify (Grafana Explore, `grafana.forge`)
- Pod logs: `{k8s_namespace_name="nico-system"}`
- Node/relay logs: (deferred — journald receiver needs a `journalctl`-capable image; see the collection table)
- Console: `{exporter="nico-ssh-console-rs"}` (label `machineid`)
- DPU logs: `{component="hbn"}`, `{component="journald"}`, `{component="dpu-auth-filelog"}`
- DPU metrics: Prometheus query for a DPU metric (via gateway `prometheus/site` → `:9999`)
- No Panoptes egress: `helm -n otel get values otel-agent` / `... otel-collector-gateway` — no
  `otlphttp/*-panoptes`, no `oauth2client`, no `logzio`.

## Replicate to another site (e.g. `launchpad-nvcert`)

Copy this whole `observability/` folder into the sibling site's deploy dir. The bundle is site-generic
except three things — change **only** these:

1. **Site label** — `OTEL_SITE_NAME` (`extraEnvs`) in `values-otel-collector-agent.yaml` and
   `values-otel-collector-gateway.yaml`, and `forge_site` in `values-kube-prometheus-stack.yaml`
   (`prometheus.externalLabels`) → the new site name (e.g. `nvcert`).
2. **The two VIPs** — pick two free IPs from that site's MetalLB pool for `otel-receiver.forge` and
   `grafana.forge`, and update: the LB annotation in `values-otel-collector-gateway.yaml` (`.30`), the
   Grafana LB in `values-kube-prometheus-stack.yaml` (`.31`), the site's `metallb-config.*.yaml` (add the
   range), and the site's unbound `localData` (`otel-receiver.forge`/`grafana.forge` records).
3. **Storage size** — optional; leave 50Gi unless the site's disk differs.

Everything else is identical across forge sites: the mTLS chain (`site-issuer`/`site-root` == the DPU's
`ca.pem`), the collector configs/pipelines, the Loki/kps values, and
`deploy-observability.sh`. Site prereqs: cert-manager + the `site-issuer`/`site-root` CA,
`local-path-persistent` StorageClass, MetalLB. **No Contour required** (that's the launchpad-native
adaptation of forged v2's front-door — §Relationship above). Run the same runbook; verify with
`{forge_site="<newsite>"}`.

## Files
`values-loki.yaml`, `values-otel-collector-agent.yaml`, `values-otel-collector-gateway.yaml`,
`values-kube-prometheus-stack.yaml`, `otel-receiver-certificate.yaml`, `deploy-observability.sh`.

## Not included
Panoptes exporter + OAuth2, Kratos/logzio audit exporters, Tempo traces (add later via forged's
`remote_values_tempo_enabled.yaml` pattern if traces are ever needed).

# NICo Flow enablement on launchpad (rg-forge-launchpad) — Flow-only fixes

**Scope:** ONLY the work to deploy NICo Flow (`nico-flow`/`nico-psm`/`nico-nsm`) and connect the site-agent to
it.

**Flow path:** site-agent (ns `nico-rest`) ↔ gRPC/mTLS ↔ `nico-flow.flow.svc.cluster.local:50051` (+ `psm:50052`, `nsm:50053`). Flow handles REST-side networking/VPC/fabric; nothing to do with rack/switch/power-shelf management.

**Outcome:** Flow `3/3 Running` on v2.1; site-agent↔Flow mTLS connected (`Successfully created Flow gRPC client`, `/v1.Flow/Version code=Ok`); `FLOW_GRPC_ENABLED=true`.

---

## 1. Flow deployment (Phase 7h)
Deployed via `launchpad-deploy/nico/deploy-flow.sh` (mirrors setup.sh Phase 7h). Fixes it bakes in:
- **image-pull-secret empty-auths clobber:** the `nico-flow` chart *owns* `image-pull-secret` with a default `dockerconfigjson = {"auths":{}}`. A manually-copied pull secret gets overwritten on `helm install` → `ImagePullBackOff` / `403 anonymous token`. **Fix:** feed real creds via `--set-string imagePullSecret.dockerconfigjson=<from nico-rest's image-pull-secret>`.
- **Missing Temporal `flow` namespace:** the original `install-rest-1.6.0.sh` only created the `cloud` + `site` Temporal namespaces; the `flow` namespace must exist or the flow workers panic on startup. `deploy-flow.sh` creates it.
- Pre-applies the flow `Certificate`s (SPIFFE + temporal-client) with Helm-ownership annotations, waits for cert-manager, fail-fasts on the DB-cred/vault-token secrets, then `helm upgrade --install flow`.

## 2. Flow DB migration-hash mismatch (v1.6 → v2.1)
When Flow was bumped to v2.1, the `flow` container went fatal:
`failed to run migrations: Hash for migration initial (20250831154717) does not match already applied migration`.
The v2.1-pr line changed the `initial` migration content, so its hash no longer matched what v1.6 recorded in the `migrations` table of the `flow` DB (on `nico-pg-cluster`, owner `flow.nico`). **Fix on a fresh site (no real flow data):**
```bash
kubectl -n flow scale deploy/flow --replicas=0
# drop + recreate the empty flow DB on nico-pg-cluster (spilo master):
kubectl -n postgres exec nico-pg-cluster-0 -c postgres -- psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='flow' AND pid<>pg_backend_pid();"
kubectl -n postgres exec nico-pg-cluster-0 -c postgres -- psql -U postgres -c "DROP DATABASE flow;"
kubectl -n postgres exec nico-pg-cluster-0 -c postgres -- psql -U postgres -c 'CREATE DATABASE flow OWNER "flow.nico";'
kubectl -n flow scale deploy/flow --replicas=1   # v2.1 migrates fresh (24 migrations) → 3/3 Running
```
(psm/nsm were unaffected.)

## 3. REST + agent upgrade v1.6.0 → v2.1.0-pr-14-g0d5452b9a (why Flow needed it)
- **site-agent v1.6 metrics-panic crashloop:** enabling `FLOW_GRPC_ENABLED=true` on v1.6 caused
  `panic: duplicate metrics collector registration attempted` (`flowgrpc/metrics.go` used `prometheus.MustRegister`; the Flow-gRPC retry loop re-registered the collector). **Fixed in v2.1** (uses `prometheus.Register` + tolerates `AlreadyRegisteredError`). So agent→Flow only works on v2.1.
- Upgraded the whole REST+Flow set (api, site-manager, site-agent, workers, flow/psm/nsm) to one tag; api schema→2.0.0 migration ran clean. Target tag found via nvcr `proxy_auth` token → `tags/list` (multi-arch manifest; nodes are amd64).
- **Gotcha — site-agent helm upgrade wipes `temporal-client-site-agent-certs`:** `resource-policy: keep` prevents deletion, NOT overwrite, so each site-agent `helm upgrade` resets that secret to the empty placeholder. After any site-agent upgrade: roll a fresh OTP (`PATCH /v2/org/ncx/nico/site/<id> {"renewRegistrationToken":true}` → patch `site-registration` secret `otp` → restart agent) so it re-handshakes and re-downloads the Temporal cert. To enable Flow WITHOUT wiping the cert, edit the CM (`FLOW_GRPC_ENABLED=true`) + `rollout restart` instead of a helm upgrade.

## 4. Connecting the site-agent to Flow (mTLS)
- The `tls: certificate required` failure seen on v1.6 was a **client-side bug fixed in v2.1** (the old client silently sent no cert on CA mismatch). Both sides share the **`vault-nico-issuer`** CA (agent presents `/etc/core-grpc` = secret `core-grpc-client-site-agent-certs`; Flow's server trusts the same CA — verified ca.crt sha match). So on v2.1 no cert/mount change was needed.
- Enable: set `FLOW_GRPC_ENABLED=true` in `nico-rest-site-agent-config` (via CM edit + `rollout restart sts/nico-rest-site-agent`, to avoid the temporal-cert wipe). Verified `Successfully created Flow gRPC client` + `/v1.Flow/Version code=Ok`. `capabilities.flow` flips true on the next site-config publish cycle.

## 5. Shared foundation fix surfaced here (also mattered beyond Flow)
### Temporal persistence DB (`postgres-0`) undersized — the big one
- **Symptom (Flow/pairing saga):** site stuck `Pending` (wouldn't pair); site-agent + worker activities (`UpdateMachinesInDB`, `RecordLatency`, etc.) hit `StartToClose` timeouts; Temporal history logged `pq: canceling statement due to user request` on `ReadHistoryBranch`.
- **Root cause:** `postgres-0` (ns `postgres`, alpine statefulset hosting `temporal` + `temporal_visibility` + `nico` + `keycloak`) capped at **512Mi/500m** → Temporal persistence reads exceeded deadline → canceled → all workflows stalled. Bumping the *workers'* CPU did nothing; the DB was the bottleneck.
- **Fix:**
  ```bash
  kubectl -n postgres set resources statefulset/postgres --limits=cpu=2,memory=4Gi --requests=cpu=1,memory=2Gi
  kubectl -n temporal rollout restart deploy/temporal-history deploy/temporal-matching deploy/temporal-frontend
  ```
  After this the site paired (`Registered`/`isOnline:true`) and workflows completed in ~2s. (Restarting all 3 Temporal services at once caused a transient `"Not enough hosts to serve the request"` membership blip — self-cleared in ~60s.)
- **Note:** this is a **shared Temporal-persistence fix**, not Flow-specific. It also unblocked the RMS-side rack-declaration/inventory Temporal workflows — see `RMS-ENABLEMENT.md §7`.

### Site registration (siteId)
The site had no `site` row → registered via `POST /v2/org/ncx/nico/site` (ProviderAdmin token from `helm-prereqs/keycloak/get-token.sh`, client `ncx-service`). **siteId `8c894583-…`**, org `ncx`. Re-pointed the site-agent (`CLUSTER_ID`/`TEMPORAL_SUBSCRIBE_NAMESPACE`) + `site-registration` secret. Automated in `register-rest-site.sh`. Needed for the agent to pair (Flow and rack ingestion both ride on a paired agent).

## Reference
- REST/Flow image `v2.1.0-pr-14-g0d5452b9a`; Flow ns `flow` (svcs `flow:50051`/`psm:50052`/`nsm:50053`)
- Scripts: `launchpad-deploy/nico/deploy-flow.sh`, `register-rest-site.sh`; token helper `helm-prereqs/keycloak/get-token.sh`
- Related: `V2-UPGRADE-PLAN.md`, `WORKLOG-2026-07-02.md`; RMS is separate → `RMS-ENABLEMENT.md`

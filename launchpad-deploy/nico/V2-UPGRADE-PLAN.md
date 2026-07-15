# Launchpad REST + Flow: v1.6.0 → v2.0.x upgrade plan

> ✅ STATUS: COMPLETED 2026-07-08 — REST + Flow are on `v2.1.0-pr-14-g0d5452b9a`, site
> `8c894583-bea4-445d-a5bd-46ee0e3cb3fb` registered (Registered/isOnline), agent↔Flow enabled
> (`FLOW_GRPC_ENABLED=true`). Kept for historical reference.


**Goal:** move the whole REST + Flow stack off v1.6.0 to the v2.0 line so the site-agent gets the
metrics-idempotency fix (no crashloop when Flow gRPC is enabled), then complete the agent↔Flow link.

**Why:** deployed v1.6.0 `nico-rest-site-agent` uses `prometheus.MustRegister` in `flowgrpc/metrics.go`; with
`FLOW_GRPC_ENABLED=true` the Flow client retry loop re-registers the collector → `panic: duplicate metrics
collector registration` → crashloop. Fixed on `release/v2.0` (uses `prometheus.Register` + tolerate dup).

**Current safe state:** `FLOW_GRPC_ENABLED=false`; agent stable, site paired/online, inventory flows, rack
ingestion works. The upgrade is only needed to turn on agent↔Flow (`capabilities.flow=true`).

## Target tag (RESOLVED)
**`T = v2.1.0-pr-14-g0d5452b9a`** — multi-arch manifest present for all 8 images (api, site-manager,
workflow, cert-manager, flow, psm, nsm, site-agent); sha = origin/main HEAD (has the metrics fix).
Nodes are amd64 (manifest resolves correctly). Registry = `nvcr.io/0837451325059433/carbide-dev`.

Helm releases / chart paths:
- `nico-rest` (rev 5, chart nico-rest-0.1.13) → `helm/rest/nico-rest`
- `nico-rest-site-agent` (rev 1, chart 0.1.9) → `helm/rest/nico-rest-site-agent`
- `flow` (rev 4) → `helm/charts/nico-flow`

### ★ MUST re-assert site-agent identity on upgrade (set outside helm during #23)
`helm upgrade` on the site-agent would revert its CM to the install-time `CLUSTER_ID=7f91b08b` (the
now-orphaned UUID — historical; the live/registered site is `8c894583-…`). Re-assert the
live values via --set: `envConfig.CLUSTER_ID=8c894583-bea4-445d-a5bd-46ee0e3cb3fb`,
`envConfig.TEMPORAL_SUBSCRIBE_NAMESPACE=8c894583-bea4-445d-a5bd-46ee0e3cb3fb`,
`envConfig.TEMPORAL_SUBSCRIBE_QUEUE=site`, `envConfig.FLOW_GRPC_ENABLED=false` (keep false until Phase 4).
The `site-registration` secret (site-uuid+OTP) was hand-created — confirm it isn't clobbered; re-seed if needed.

## Two blockers this upgrade addresses (and one it may not)
1. ✅ metrics panic → fixed by the v2.0 site-agent image.
2. ❓ **Flow mTLS**: the `release/v2.0` site-agent chart still mounts only `/etc/core-grpc` (no spiffe mount),
   and Flow rejected the agent with `tls: certificate required`. The bump makes this **retry gracefully instead
   of crashing**, but `capabilities.flow` won't flip until the cert is resolved. Treat as a Phase-4 follow-up.
   (it was solved — see [FLOW-FIXES.md](../FLOW-FIXES.md).)

## Pre-flight (do first — no mutations)
- [ ] Confirm tag `T` (above).
- [ ] Confirm helm release names: `helm -n nico-rest list -a` and `helm -n flow list -a`
      (expected: `nico-rest`, `nico-rest-site-agent` in nico-rest; `flow` in flow).
- [ ] Review REST DB migrations that fire v1.6.0→`T` (image `nico-rest-db:T`, pre-upgrade hook). Know what changes.
- [ ] **Back up** the REST DBs on `postgres-0`:
      ```bash
      for db in nico elektratest keycloak temporal temporal_visibility; do
        kubectl -n postgres exec postgres-0 -- pg_dump -U postgres "$db" > /tmp/rest-$db.$(date +%s).sql; done
      ```
- [ ] Snapshot values: `helm -n nico-rest get values nico-rest > /tmp/nico-rest.values.yaml` (+ site-agent, flow).
- [ ] Record the site identity: siteId `8c894583-bea4-445d-a5bd-46ee0e3cb3fb`, org `ncx`, provider `6558fca2…`.
- [ ] Keep `FLOW_GRPC_ENABLED=false` for Phases 1–3.

## Phase 1 — REST core (api, site-manager, workflow, cert-manager) → T
```bash
helm -n nico-rest upgrade nico-rest <chart> -f /tmp/nico-rest.values.yaml --set global.image.tag=T --wait
```
- Watch the schema-migration Job (`nico-rest-db`, pre-upgrade hook) → must succeed.
- Verify: `curl .../healthz`, `GET /v2/org/ncx/nico/site` still returns the site (migration preserved it),
  keycloak realm `nico` intact.

## Phase 2 — site-agent → T (still FLOW off)
```bash
helm -n nico-rest upgrade nico-rest-site-agent <chart> --set global.image.tag=T --wait
```
- Verify pods `Running` (expect restart≤1), agent re-pairs, site `Registered`/`isOnline`, inventory flows.

## Phase 3 — Flow (flow/psm/nsm) → T
```bash
TAG=T ./launchpad-deploy/nico/deploy-flow.sh
```
- Verify `flow` 3/3 Running.

## Phase 4 — enable + fix agent↔Flow
- Set `FLOW_GRPC_ENABLED=true`, restart site-agent.
- Pods must stay `Running` (no metrics panic — the v2.0 fix). If Flow gRPC still logs `tls: certificate
  required`, resolve the cert: identify the CA Flow's gRPC server trusts vs the cert the agent presents
  (`/etc/core-grpc`); mount/point the agent at an accepted cert (likely a spiffe cert from the same issuer as
  `flow-certificate`). May require a site-agent chart change (add spiffe volume + set the flowgrpc cert path).
- Success = `capabilities.flow: true` on the site.

## Phase 5 — persist + verify
- Update `launchpad-deploy/nico/nico-core.launchpad.yaml` + any image-tag values to `T`; commit to launchpad-deployment.
- Final: site `Registered`/`isOnline`/`capabilities.flow=true`, inventory + rack ingestion healthy, no crashloops.

## Rollback
- Schema migration is forward-only. Rollback = `helm rollback` each release to the v1.6.0 revision **and**
  restore the DB dumps from pre-flight. Set `FLOW_GRPC_ENABLED=false`.

## Risks
- Brief api(v2.0)↔agent(v1.6.0) version skew between Phase 1 and 2 — keep the window short.
- DB migration is the highest-risk step — backups are mandatory.
- Flow mTLS (Phase 4) may need real cert work; not guaranteed by the image bump alone. (it was solved
  — see [FLOW-FIXES.md](../FLOW-FIXES.md).)

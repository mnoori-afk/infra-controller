# RMS enablement on launchpad (rg-forge-launchpad) — RMS-only changes

**Scope:** ONLY the changes that made NICo talk to RMS (rack / switch / power-shelf management).

**Outcome — verified working:** RMS logs show nico-api calling it over mTLS:
`rpc_method=BatchGetPowerState  status=200  peer_identity="CN=nico-api.nico-system.svc.cluster.local"  node_type=powershelf_gb300_liteon  rack=launchpad-r1`.

**RMS path (the only thing that matters here):** `nico-api` (Core, `v2.0.0-pr-503`) `component_manager` → gRPC/mTLS → `rms-api-server.rack-manager.svc.cluster.local:8801`. No Flow, no REST v2.1 involved.

---

## 1. nico-system siteConfig changes (the rack + component-manager + RMS config)

Added to the siteConfig (CM **`nico-api-site-config-files`**, keys `nico-api-site-config.toml` + `carbide-api-site-config.toml`), rendered from `launchpad-deploy/nico/nico-core.launchpad.yaml` → `nico-api.nicoApiSiteConfig`:

```toml
[site_explorer]
enabled = true
run_interval = "30s"
allow_zero_dpu_hosts = false        # ⚠ NOT a real field in pr-503 SiteExplorerConfig → silently ignored (no-op)
create_switches = true
create_power_shelves = true
explore_mode = "nv-redfish"         # pre-existing, required for GB300

[rack_profiles.NVL72_GB300]
product_family = "gb300"
rack_hardware_topology = "gb300_nvl72r1_c2g4_topology"
[rack_profiles.NVL72_GB300.rack_capabilities.compute]      # name=GB300, count=18, vendor=Lenovo
[rack_profiles.NVL72_GB300.rack_capabilities.switch]       # count=9,  vendor=NVIDIA
[rack_profiles.NVL72_GB300.rack_capabilities.power_shelf]  # count=6,  vendor=LiteOn

[component_manager]
nv_switch_backend = "rms"
power_shelf_backend = "rms"
compute_tray_backend = "rms"
nv_switch_use_state_controller = true
power_shelf_use_state_controller = true
compute_tray_use_state_controller = true

[rms]
api_url = "https://rms-api-server.rack-manager.svc.cluster.local:8801"
enforce_tls = true
root_ca_path = "/var/run/secrets/spiffe.io/ca.crt"    # see §2 (translated from ticket's [rms.tls])
client_cert  = "/var/run/secrets/spiffe.io/tls.crt"
client_key   = "/var/run/secrets/spiffe.io/tls.key"
```

**Typo fix (mandatory):** the ticket repeatedly wrote `[rack_profiles.NVL72_300.rack_capabilities.power_shelf]`; the profile is `NVL72_GB300`. With the typo, `power_shelf_backend="rms"` startup validation rejects the profile (missing power_shelf vendor) and **nico-api won't boot**.

## 2. RMS mTLS wiring (the key correctness fix)

The Jira ticket specified `[rms.tls] cert_dir = "/var/run/secrets/spiffe.io"`, **but that subtable does not exist in pr-503's `RmsConfig`** — it uses flat `root_ca_path`/`client_cert`/`client_key`/`enforce_tls`. As written, `[rms.tls]` was silently ignored (nico-api parsed `root_ca_path: None, client_cert: None, client_key: None`) → mTLS would fail the moment RMS was called.

**Fix = translate to the flat pr-503 fields**, pointing at the spiffe cert nico-api already mounts:
- nico-api mounts secret **`nico-api-certificate`** (ClusterIssuer **`vault-nico-issuer`**) at **`/var/run/secrets/spiffe.io`** → files `ca.crt`/`tls.crt`/`tls.key`.
- `rms-api-server` runs `--tls-cert/--tls-key/--tls-ca`; its server cert + client-CA are also **`vault-nico-issuer`**.
- **Verified same CA:** `nico-api-certificate` `ca.crt` sha == `rms-api-server-certificate` `ca.crt` sha → mTLS succeeds (nico-api presents its cert, RMS's `--tls-ca` trusts it; nico-api verifies RMS's server cert with the same CA). No new secret/mount needed.

## 3. How it was applied (CM patch + rollout — NOT `helm upgrade`)

The `nico` helm release is stuck **failed** (SSA configmap-ownership conflict on `nico-api-site-config-files`), and nico-api has **no `checksum/config`** annotation (a helm CM change wouldn't auto-rollout). So we patch the CM directly from the file and roll nico-api:
```bash
# build /tmp/siteconfig-patch.json from nico-core.launchpad.yaml (extract nicoApiSiteConfig; write BOTH CM keys)
kubectl -n nico-system get cm nico-api-site-config-files -o yaml > /tmp/nico-api-site-cm.bak.$(date +%s).yaml
kubectl -n nico-system patch cm nico-api-site-config-files --type merge --patch-file /tmp/siteconfig-patch.json
kubectl -n nico-system rollout restart deploy/nico-api
```
nico-api parsed it cleanly (no `Invalid configuration`); `switch_controller`/`power_shelf_controller` began iterating.

## 4. RMS deployment + rack declarations

- **RMS deployed** (by the team) into ns `rack-manager`: `rms-api-server` Deployment + Service on `8801`, gRPC `mode=mTLS`. Dev-mode notes: **in-memory persistence** (`no --db-url` → state lost on restart) and **`--insecure-switch`** (RMS↔switch comms unverified) — tighten for prod.
- **Rack + components declared** via REST v2 API (`POST /v2/org/ncx/nico/{expected-rack,expected-switch,expected-power-shelf}`): rack `launchpad-r1` / profile `NVL72_GB300`; switch BMC `root`/`Buynvidia2026!` + NVOS `admin`; power-shelf BMC `root`/`0penBmc!`.

## 5. Verification
```
rack list            → launchpad-r1  state=Created
managed-switch show  → 3 switches, state=ready
rms-api-server logs  → BatchGetPowerState 200, peer_identity CN=nico-api…, node_type=powershelf_gb300_liteon
```

## 6. Known remaining issues (rack-ingestion domain — not RMS-service problems)
1. **Switches 3/9:** BMCs `.120/.122/.123/.124/.125/.134` got a 401 → site-explorer **latched into AvoidLockout** (`NICO-SITEEXPLORER-144`, DB-persisted). Fix: verify/set correct BMC creds, then `site-explorer refresh <ip>` to clear the latch.
2. **Power shelves:** 6 LiteOn BMCs (`.85/.117/.118/.136/.139/.143`) fail site-explorer's Redfish probe — **"BMC vendor field is not populated. Unsupported BMC"** (`bmc_endpoint_explorer.rs:567`). 2 shelves are managed via RMS (RMS reports their power state), so power shelves likely ingest via the RMS path — needs a NICo LiteOn power-shelf handler or excluding those BMC IPs from generic exploration.
3. **`bmc_retain_credentials=false`** → `expected_switch` rows show empty `bmc_username`/`bmc_password` by design (creds rotate into Vault at `secrets/machines/bmc/<BMC_MAC>/root`, not kept plaintext on the row).

## 7. Prerequisites we relied on (NOT RMS changes — documented in FLOW-FIXES.md)
RMS did not require the Flow work, but two shared items had to be healthy for the rack declarations/inventory to reach Core:
- **Temporal/`postgres-0` scaling** — the `expected-rack`/`expected-switch`/`expected-power-shelf` declarations propagate **REST → site-agent → Core via Temporal workflows** (`CreateExpectedRack`, etc.), and inventory runs on Temporal. While `postgres-0` (Temporal DB) was undersized, those workflows stalled. Fixed in the Flow/pairing saga (see FLOW-FIXES.md §Temporal). The RMS mTLS call itself is a direct gRPC and touches neither Flow nor Temporal.
- **Site registration** (siteId `8c894583`, org `ncx`) — needed for the site-agent↔Core sync path.
- **NOT needed:** the REST v2.1 upgrade. RMS is parsed/driven by Core (nico-api pr-503), which was never upgraded.

## Reference
- siteId `8c894583-bea4-445d-a5bd-46ee0e3cb3fb` · org `ncx` · provider `6558fca2-f07e-439b-ae32-bba1d8169380`
- Core `v2.0.0-pr-503-g49a48a69d`; RMS ns `rack-manager`, `rms-api-server…:8801`, mTLS via `vault-nico-issuer`
- Config source-of-truth: `launchpad-deploy/nico/nico-core.launchpad.yaml` (+ `RACK-CONFIG.md`)

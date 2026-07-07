# Rack + Component-Manager config for launchpad — what to apply & how it diverges

Jira: **"Setup rack and component manager configs in NICo"** (assigned to Milad).

Two versions existed — the **Jira ticket spec** and a **coworker's RMS-backed block**. After team review we apply
the **coworker's RMS-backed variant** (all backends `rms`, state controllers `true`) — with **one bug fixed** (see
below). This doc records the applied config and every way it diverges from the ticket, validated against the
api-core schema (`crates/api-model/src/rack_type.rs`, `crates/component-manager/src/config.rs`).

## ✅ FINAL config we apply (coworker RMS variant, typo fixed)

```toml
# added into the EXISTING [site_explorer] table (do NOT create a 2nd [site_explorer])
[site_explorer]
create_switches = true
create_power_shelves = true

[rack_profiles.NVL72_GB300]
product_family = "gb300"
rack_hardware_topology = "gb300_nvl72r1_c2g4_topology"

[rack_profiles.NVL72_GB300.rack_capabilities.compute]
name = "GB300"
vendor = "Lenovo"
count = 18

[rack_profiles.NVL72_GB300.rack_capabilities.switch]
vendor = "NVIDIA"
count = 9

[rack_profiles.NVL72_GB300.rack_capabilities.power_shelf]   # was NVL72_300 (TYPO) — FIXED
vendor = "LiteOn"
count = 6

[component_manager]
compute_tray_backend = "rms"
nv_switch_backend = "rms"
power_shelf_backend = "rms"
nv_switch_use_state_controller = true
power_shelf_use_state_controller = true
compute_tray_use_state_controller = true

[rms]
api_url = "http://rms-api-server.rack-manager:8801"
enforce_tls = false
```

## ★ The one bug we fixed in the source draft
`[rack_profiles.NVL72_300.rack_capabilities.power_shelf]` → **`NVL72_GB300`**. Because
`power_shelf_backend = "rms"`, the startup validator (`validate_rms_backend_rack_profiles`) requires a
`power_shelf.vendor` on the `NVL72_GB300` profile. With the typo that capability attached to a phantom
`NVL72_300` profile, so `NVL72_GB300` had no power_shelf → `Invalid configuration` → **nico-api would not boot**.

## Divergence: applied (coworker RMS) vs the Jira ticket spec
| # | Field | Applied (coworker RMS) | Jira ticket | Impact |
|---|---|---|---|---|
| 1 | profile name | `NVL72_GB300` | `NVL72` | map key; verify against expected-racks reference |
| 2 | type key | `product_family = "gb300"` | `rack_hardware_type = "any"` | both valid; applied uses the specific product family |
| 3 | `compute_tray_backend` | `rms` | `core` | applied routes compute trays through RMS too |
| 4 | `*_use_state_controller` | `true` (all 3) | `false` (all 3) | **applied actively drives components via RMS** |
| 5 | `[component_manager.nsm]` / `[.psm]` | **absent** | present (→ Flow svcs) | not needed while backends are `rms` (only used for nsm/psm backends) |
| + | `[site_explorer] create_*` | present | absent | needed so the 9 switch + 6 shelf objects get created |

## Behavior before RMS is deployed
- **nico-api still starts** — a backend of `"rms"` only requires the RMS *client* to be *configured* (the `[rms]`
  block is present); the TCP connect is **lazy**.
- **BUT** `*_use_state_controller = true` means the switch/power-shelf/compute state controllers actively call
  `rms-api-server.rack-manager:8801` and will **error/retry until RMS is deployed** (noisy logs, rack management
  ops don't complete). Switch/shelf *discovery/creation* (`create_*`) still works via Redfish.
- This is more RMS-dependent than the ticket's variant (which used `core` + controllers off). Chosen per team.

## Apply procedure (live)
1. Insert the two `create_*` into the EXISTING `[site_explorer]` table + append the rack tables — done in
   `nico-core.launchpad.yaml` (deploy + bringup, in sync).
2. Patch the live `nico-api-site-config-files` CM (both `nico-api-site-config.toml` and `carbide-api-site-config.toml` keys).
3. `kubectl -n nico-system rollout restart deploy/nico-api` and watch it come up (no `Invalid configuration`).
4. Verify switches/power-shelves get created; expect RMS state-controller errors in logs until RMS lands.

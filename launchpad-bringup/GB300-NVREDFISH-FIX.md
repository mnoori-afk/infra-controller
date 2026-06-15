# GB300 ingestion fix — nv-redfish `LenovoAmi` chassis quirk

_Written 2026-06-15 during launchpad GB300 NVL72 bring-up. This is the note to read if you later ask
"what was the GB300 ingestion code change and why."_

Related: [STATUS.md](STATUS.md) · [DHCP-RELAY.md](DHCP-RELAY.md) · memory `project_nico_pxe_ingestion_gotchas` (#16/#17).

---

## TL;DR
The 18 GB300 Lenovo compute-tray BMCs could not be **ingested** even though everything site-side was
healthy (DHCP relay, underlay segment, creds, Redfish auth all verified). Root cause was a hardware
quirk the upstream `nv-redfish` Redfish client didn't yet handle. We forked `nv-redfish`, added a
3-edit fix, and pointed NICo at the fork to build a custom `nvmetal-carbide` image for launchpad.

## The bug (precise)
- A GB300 tray BMC exposes **two** Redfish Systems: `HGX_Baseboard_0` (NVIDIA GPU board, **no** BIOS)
  and `System_0` (Lenovo HG635N_V2 host, **has** BIOS). The default `explore_mode="libredfish"`
  picked the first System (`HGX_Baseboard_0`) and 404'd on its missing `/Bios` → 0 machines.
  **Fix part 1 (config, already applied):** set `[site_explorer] explore_mode = "nv-redfish"` in the
  NICo siteConfig (`launchpad-bringup/nico/nico-core.launchpad.yaml`). That cleared the BIOS-404.
- Under `nv-redfish`, exploration then failed deserializing the **chassis collection**:
  `bmc-explorer/src/chassis.rs:62` → `missing field 'ChassisType'`. nv-redfish *has* a workaround
  (`add_default_chassis_type`, injects `ChassisType:"Other"` only when absent) but it's gated behind a
  **platform quirk** `bug_missing_chassis_type_field()` that returns true only for `Platform::AmiViking`.
- nv-redfish classifies platform purely from the ServiceRoot `Vendor`/`RedfishVersion`/`Product`
  (`bmc_quirks.rs::BmcQuirks::new`). The GB300 tray BMC reports **`Vendor == "Lenovo"`** (its AMI
  MegaRAC identity is only inside the `Oem` block, which nv-redfish never reads) → matched no arm →
  `Platform = None` → the chassis patches never registered → parse failed → **0 machines ingested**.
- Confirmed this is unfixed across **all** nv-redfish versions including `main` HEAD (tags up to
  v0.10.2; none broaden the quirk). It is NOT fixable from infra-controller-core (the `Platform`/quirk
  types are `pub(crate)`, auto-detected; NICo only calls `ServiceRoot::new(bmc)` with no override hook,
  and NICo's own `is_gb300()` runs *after* the failing parse).

## The fix (two repos)

### 1. `nv-redfish` (the actual fix) — repo `github.com/NVIDIA/nv-redfish`
- Fork: `github.com/mnoori-afk/nv-redfish`, branch **`gb300-lenovo-chassis-quirk`** (based on tag `v0.10.0`).
- File `redfish/src/bmc_quirks.rs`, 3 edits:
  1. Add `Platform::LenovoAmi` enum variant.
  2. Add classifier arm `Some("Lenovo") => Some(Platform::LenovoAmi)` (before `_ => None`).
  3. OR `LenovoAmi` into `bug_missing_chassis_type_field()` and `bug_missing_chassis_name_field()`:
     `matches!(self.platform, Some(Platform::AmiViking | Platform::LenovoAmi))`.
- Why a **distinct** `LenovoAmi` (not reuse `AmiViking`): AmiViking also enables Viking
  systems/managers `odata_id` filters that would drop the Lenovo host's `System_0`/Manager members.
  `LenovoAmi` enables ONLY the two chassis defaults (both no-ops when the field is present), so it's safe.
- Upstream MR: open `mnoori-afk/nv-redfish:gb300-lenovo-chassis-quirk` → `NVIDIA/nv-redfish`. (The team
  may want to narrow `Some("Lenovo")` to the GB300 product, but the defaults are harmless for any Lenovo.)

### 2. `infra-controller-core` (the wiring) — repo `github.com/NVIDIA/infra-controller-core`
- Fork: `github.com/mnoori-afk/infra-controller`, branch **`gb300-lenovo-nvredfish-fix`**.
- `Cargo.toml` `[workspace.dependencies]`: changed `nv-redfish = { version = "0.10.0" }` to a **git
  dependency** on the fork branch. (A direct git dep is used, not `[patch.crates-io]`, because the
  nv-redfish source carries workspace version `0.1.0` — release tooling bumps it to `0.10.0` at publish
  — so a `[patch]` keyed to `"0.10.0"` would be silently ignored. A git dep sidesteps version matching.)
- This is a **temporary bring-up change**. Once NVIDIA/nv-redfish releases the fix, revert to a
  crates.io `version = "<released>"`.

## Build / deploy (custom image for launchpad)
- Build the `nvmetal-carbide` x86_64 image (SC nodes are x86_64) via the repo build container
  (`cargo make build-cargo-docker-image-minimal` then `cargo make cargo-docker-minimal -- build ...`,
  or the project's image build task). Tag e.g. `v2.0.0-pr-70-gb300fix`.
- Push to `nvcr.io/0837451325059433/carbide-dev` (needs nvcr write access).
- Deploy WITHOUT a full reinstall: `helm upgrade --install nico ./helm -n nico-system -f
  launchpad-bringup/nico/nico-core.launchpad.yaml --set-string global.image.tag=<new-tag> …` then
  `kubectl -n nico-system rollout restart deploy/nico-api`. Vault creds, expected_machines, and BMC
  leases all persist.
- Verify: `nico-api` logs show the chassis collection parsing (no more `ChassisType`), `explore_site`
  `endpoint_explorations_success > 0`, and `ac machine show` populating → trays drive to `Ready`.

## Caveat — expect to iterate
GB300 ingestion is WIP upstream ("No GB300 is deployed today"). Clearing the chassis parse may surface
the **next** GB300 Redfish gap (host System/Manager parsing, BIOS attrs, etc.). The loop is: build →
deploy → read the next `Failed to explore` error → add the next nv-redfish quirk → rebuild. Each round
is one more small quirk in `bmc_quirks.rs` on the same fork branch.

#!/usr/bin/env bash
# ingest-rack-components.sh — declare the 9 NVLink switches + 6 power shelves for rack
# nvcert-r1 via admin-cli (writes to Core expected_switches / expected_power_shelves,
# matching the working launchpad deploy). This is what triggers ensure_rack_exists ->
# creates the `racks` row -> rack_controller manages it -> RMS starts BatchGetPowerState.
#
# Data is verified in inventory.md (docs + ToR fdb + DHCP leases + BMC Redfish).
# Idempotent-ish: `expected-switch add` errors if the switch already exists; re-run after
# a `remove` if you need to change a value, or use `expected-switch update`.
#
# Usage:
#   export KUBECONFIG=$HOME/.kube/launchpad-nvcert.config
#   ./ingest-rack-components.sh            # do everything
#   ./ingest-rack-components.sh switches   # switches only
#   ./ingest-rack-components.sh shelves    # power shelves only
set -euo pipefail
: "${KUBECONFIG:?export KUBECONFIG=\$HOME/.kube/launchpad-nvcert.config first}"

AC=(kubectl -n nico-system exec deploy/admincli -- /opt/carbide/carbide-admin-cli)
RACK="nvcert-r1"

# name  serial  bmc_mac  nvos_mac   (BMC root/Buynvidia2026!, NVOS admin/Buynvidia2026!)
SWITCHES=(
"nvlink-switch-1 MT2544602NNP 20:4d:52:d8:87:fe 60:5e:65:97:97:5e"
"nvlink-switch-2 MT2544602NHD 20:4d:52:d8:5c:3e 60:5e:65:ad:14:00"
"nvlink-switch-3 MT2544602NH5 20:4d:52:d8:5a:3e 60:5e:65:ac:b6:32"
"nvlink-switch-4 MT2544602NHB 20:4d:52:d8:5b:be 60:5e:65:ac:b6:4a"
"nvlink-switch-5 MT2544602NJ8 20:4d:52:d8:63:3e 60:5e:65:ad:25:78"
"nvlink-switch-6 MT2544602NNM 20:4d:52:d8:87:7e 60:5e:65:97:8f:ae"
"nvlink-switch-7 MT2544602NH0 20:4d:52:d8:58:fe 60:5e:65:ac:b6:5a"
"nvlink-switch-8 MT2544602NDA 20:4d:52:d8:3a:7e 60:5e:65:be:8c:ae"
"nvlink-switch-9 MT2544602NJC 20:4d:52:d8:64:3e 60:5e:65:97:98:be"
)

# name  serial  bmc_mac   (BMC root/0penBmc)
SHELVES=(
"powershelf-1 613337RBX04X15342TX 24:5b:f0:81:e9:84"
"powershelf-2 613337RBX04X15342TV 24:5b:f0:81:e9:2f"
"powershelf-3 613337RBX04X15342U7 24:5b:f0:81:e7:ce"
"powershelf-4 613337RBX04X15342TU 24:5b:f0:81:e6:9c"
"powershelf-5 613337RBX04X15342TY 24:5b:f0:81:e9:87"
"powershelf-6 613337RBX04X15342U2 24:5b:f0:81:e6:b4"
)

add_switches() {
  echo "== adding 9 NVLink switches to rack ${RACK} =="
  for row in "${SWITCHES[@]}"; do
    read -r name ser bmc nvos <<< "$row"
    "${AC[@]}" expected-switch add \
      --bmc-mac-address "$bmc" --bmc-username root --bmc-password 'Buynvidia2026!' \
      --switch-serial-number "$ser" \
      --nvos-mac-address "$nvos" --nvos-username admin --nvos-password 'Buynvidia2026!' \
      --rack_id "$RACK" --meta-name "$name" \
      --label site:nvcert --label rack:nvcert-r1 \
      --label manufacturer:NVIDIA --label model:N5500_LD \
      && echo "  + $name ($ser)" || echo "  ! $name FAILED (already exists? see error above)"
  done
}

add_shelves() {
  echo "== adding 6 power shelves to rack ${RACK} =="
  for row in "${SHELVES[@]}"; do
    read -r name ser bmc <<< "$row"
    "${AC[@]}" expected-power-shelf add \
      --bmc-mac-address "$bmc" --bmc-username root --bmc-password '0penBmc' \
      --shelf-serial-number "$ser" \
      --rack_id "$RACK" --meta-name "$name" \
      --label site:nvcert --label rack:nvcert-r1 \
      --label manufacturer:LiteOn --label model:PF-1333-7RB \
      && echo "  + $name ($ser)" || echo "  ! $name FAILED (already exists? see error above)"
  done
}

# Component BMC IPs (from inventory.md). Needed for the refresh loop below.
SWITCH_IPS="172.16.2.77 172.16.2.76 172.16.2.79 172.16.2.63 172.16.2.82 172.16.2.70 172.16.2.75 172.16.2.78 172.16.2.73"
SHELF_IPS="172.16.2.71 172.16.2.80 172.16.2.81 172.16.2.74 172.16.2.72 172.16.2.68"
PG="${PG:-nico-pg-cluster-0}"

# Declaring an expected-switch/shelf is NOT enough — the real switch/power_shelf object is
# only materialized when site-explorer creates it during a cycle where the BMC is freshly
# explored. A single `site-explorer refresh` per component is unreliable, AND:
#   - power_shelves_created_per_run = 1  → only ONE shelf materializes per cycle (they trickle in)
#   - power-shelf BMCs reset during credential rotation → need a SECOND exploration after reset
# So we loop: refresh every BMC, wait, re-check, repeat until switches=9 and power_shelves=6.
_count() { kubectl -n postgres exec "$PG" -- su postgres -c \
  "psql -d nico_system_nico -tAc \"SELECT count(*) FROM $1\"" 2>/dev/null | tr -d '[:space:]'; }

refresh_until_materialized() {
  echo "== refreshing BMCs until all objects materialize (switches=9, power_shelves=6) =="
  for pass in $(seq 1 10); do
    for ip in $SWITCH_IPS $SHELF_IPS; do
      "${AC[@]}" site-explorer refresh "$ip" >/dev/null 2>&1 && printf '.'
      sleep 3
    done
    sw=$(_count switches); ps=$(_count power_shelves)
    echo " | pass $pass: switches=$sw/9 power_shelves=$ps/6"
    [ "$sw" = "9" ] && [ "$ps" = "6" ] && { echo "ALL MATERIALIZED"; return 0; }
    sleep 30
  done
  echo "WARNING: not fully materialized after 10 passes — re-run, or refresh the lagging BMC IPs individually."
}

case "${1:-all}" in
  switches) add_switches ;;
  shelves)  add_shelves ;;
  refresh)  refresh_until_materialized ;;
  all)      add_switches; echo; add_shelves; echo; refresh_until_materialized ;;
  *) echo "usage: $0 [all|switches|shelves|refresh]"; exit 1 ;;
esac

echo ""
echo "== verify =="
echo "  ${AC[*]} rack show                 # want: Switches 9, Power Shelves 6"
echo "  ${AC[*]} expected-switch show ; ${AC[*]} expected-power-shelf show"
echo "  kubectl -n rack-manager logs deploy/rms-api-server | grep BatchGetPowerState  # 200, peer CN=nico-api"

#!/usr/bin/env bash
#
# Render the expected-machines JSON from the committed template by substituting
# secrets from your environment. The OUTPUT file contains the real BMC password
# in cleartext — it is written next to this script and must NOT be committed
# (see the .gitignore in this directory).
#
# Usage:
#   export BMC_PASSWORD='<the tray/DPU BMC password>'   # from 1Password, do NOT paste into a file
#   ./render.sh
#   # -> writes expected_machines.launchpad.json  (git-ignored)
#
set -euo pipefail
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${BMC_PASSWORD:?set BMC_PASSWORD (get it from 1Password / the team) before rendering}"

TEMPLATE="${_DIR}/expected_machines.launchpad.template.json"
OUT="${_DIR}/expected_machines.launchpad.json"

# Only substitute BMC_PASSWORD (envsubst would also expand any other $VAR in the file).
BMC_PASSWORD="${BMC_PASSWORD}" envsubst '${BMC_PASSWORD}' < "${TEMPLATE}" > "${OUT}"

# sanity: valid JSON, placeholder fully replaced
python3 -c "import json,sys; json.load(open('${OUT}')); sys.exit(0)" \
  && grep -q '${BMC_PASSWORD}' "${OUT}" && { echo "ERROR: placeholder not substituted"; exit 1; } || true
echo "Wrote ${OUT} (git-ignored). Apply with:"
echo "  kubectl -n nico-system exec -i deploy/admincli -- /opt/carbide/carbide-admin-cli expected-machine replace-all < \"${OUT}\""

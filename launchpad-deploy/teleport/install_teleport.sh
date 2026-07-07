#!/usr/bin/env bash
# install_teleport.sh — enroll a launchpad site-controller into Teleport via TPM join.
# Replicates stardrive's OS enrollment (site_controller_installer post_reboot_install.sh),
# but standalone since we did NOT use the stardrive ISO. Run as root on each node
# (launchpad-control-plane-1/-2/-3) after Phase 1 networking is up.
#
# Join method is TPM attestation (--join-method=tpm), NOT a bare secret. The "token" is the
# NAME of a provision-token resource on the nv-stg auth server that whitelists allowed TPM EKs.
# SERVER-SIDE PREREQ: each node's TPM EK must be registered against that token before
# `teleport start` will successfully join (see step 2 output + PHASE2 doc).
set -euo pipefail

# --- inputs (export before running) ---
server="${TELEPORT_SERVER:?set TELEPORT_SERVER, e.g. nv-stg-dgxc.teleport.sh:443}"
token="${TELEPORT_TOKEN:?set TELEPORT_TOKEN (provision-token NAME on the auth server)}"
resource_group="${TELEPORT_RESOURCE_GROUP:?set TELEPORT_RESOURCE_GROUP (node label; stardrive convention = forge)}"
environment="${TELEPORT_ENVIRONMENT:?set TELEPORT_ENVIRONMENT (node label, e.g. non-prod)}"
site="${TELEPORT_SITE:-launchpad}"   # node label (matches dev8 example: site=<site>)

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# --- preflight: TPM + proxy reachability ---
[ -e /dev/tpmrm0 ] || { echo "ERROR: no /dev/tpmrm0 — TPM 2.0 required for tpm join"; exit 1; }
echo "== reachability to ${server} =="
curl -fsS "https://${server%%:*}/webapi/ping" >/dev/null \
  || { echo "ERROR: cannot reach https://${server%%:*}/webapi/ping — check egress/proxy to the Teleport proxy"; exit 1; }

# 1) Install the version-matched agent FROM the proxy (must match server version; needs egress).
curl -fsSL "https://${server}/scripts/install.sh" -o /tmp/teleport_install.sh
bash /tmp/teleport_install.sh

# 2) Publish this node's TPM identity so its EK can be registered on the auth server.
echo "===== TPM IDENTITY (give this to whoever administers the ${server} provision token) ====="
tbot tpm identify | tee -a /etc/ssh/banner
echo "==============================================================================="

# 3) Generate /etc/teleport.yaml — TPM join, with resource-group/environment labels.
#    nodename defaults to the OS hostname (already launchpad-control-plane-N -> keeps 3-way alignment).
teleport node configure \
    --output=/etc/teleport.yaml \
    --join-method=tpm \
    --token="${token}" \
    --proxy="${server}" \
    --labels="environment=${environment},resource-group=${resource_group},site=${site}"

# 4) Enable + start, and turn on managed auto-updates.
systemctl enable teleport
systemctl start teleport
teleport-update enable --proxy "${server}" || true

echo "Done. Enrolled $(hostname) against ${server} (labels: resource-group=${resource_group}, environment=${environment})."
echo "If 'systemctl status teleport' shows a join failure, the node's TPM EK is not yet registered to token '${token}'."

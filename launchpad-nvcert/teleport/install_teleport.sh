#!/usr/bin/env bash
# install_teleport.sh — enroll an nvcert site-controller into Teleport via TPM join.
# Identical mechanism to launchpad (launchpad-deploy/teleport/install_teleport.sh).
# Run as root on each node (cp-1 through cp-3, or any additional workers) after
# networking is up (netplan/cp-N configs applied, bond0 at 172.16.2.11/12/13).
#
# Join method: TPM attestation (--join-method=tpm). The "token" is the NAME of a
# provision-token resource on nv-stg that whitelists each node's TPM EK hash.
# SERVER-SIDE PREREQ: register the EK hashes in nvcert-token.yaml on nv-stg BEFORE
# (or shortly after) running this — Teleport retries joining until the token exists.
#
# Usage (from bastion, push then run on each node):
#   for ip in 11 12 13; do scp install_teleport.sh nvidia@172.16.2.$ip:/tmp/; done
#
#   sudo TELEPORT_SERVER=nv-stg-dgxc.teleport.sh:443 \
#        TELEPORT_TOKEN=rg-forge-<SITE_NAME>-nodes-tpm \
#        TELEPORT_RESOURCE_GROUP=forge \
#        TELEPORT_ENVIRONMENT=non-prod \
#        TELEPORT_SITE=<SITE_NAME> \
#        bash /tmp/install_teleport.sh
set -euo pipefail

# --- inputs (export before running) ---
server="${TELEPORT_SERVER:?set TELEPORT_SERVER, e.g. nv-stg-dgxc.teleport.sh:443}"
token="${TELEPORT_TOKEN:?set TELEPORT_TOKEN (provision-token NAME on the auth server)}"
resource_group="${TELEPORT_RESOURCE_GROUP:?set TELEPORT_RESOURCE_GROUP (stardrive convention = forge)}"
environment="${TELEPORT_ENVIRONMENT:?set TELEPORT_ENVIRONMENT (e.g. non-prod)}"
site="${TELEPORT_SITE:-nvcert}"   # node label — set TELEPORT_SITE to the agreed site name

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# --- preflight: TPM + proxy reachability ---
[ -e /dev/tpmrm0 ] || { echo "ERROR: no /dev/tpmrm0 — TPM 2.0 required for tpm join"; exit 1; }
echo "== reachability to ${server} =="
curl -fsS "https://${server%%:*}/webapi/ping" >/dev/null \
  || { echo "ERROR: cannot reach https://${server%%:*}/webapi/ping"; exit 1; }

# 1) Install the version-matched agent from the proxy.
curl -fsSL "https://${server}/scripts/install.sh" -o /tmp/teleport_install.sh
bash /tmp/teleport_install.sh

# 2) Print this node's TPM EK hash — collect this and add to nvcert-token.yaml on nv-stg.
echo "===== TPM IDENTITY — copy ek_public_hash into nvcert-token.yaml on nv-stg ====="
tbot tpm identify | tee -a /etc/ssh/banner
echo "==============================================================================="

# 3) Generate /etc/teleport.yaml — TPM join.
#    nodename defaults to OS hostname (should be nvcert-control-plane-N).
teleport node configure \
    --output=/etc/teleport.yaml \
    --join-method=tpm \
    --token="${token}" \
    --proxy="${server}" \
    --labels="environment=${environment},resource-group=${resource_group},site=${site}"

# 4) Enable + start.
systemctl enable teleport
systemctl start teleport
teleport-update enable --proxy "${server}" || true

echo "Done. Enrolled $(hostname) (labels: resource-group=${resource_group}, environment=${environment}, site=${site})."
echo "If 'systemctl status teleport' shows a join failure, the TPM EK is not yet in nvcert-token.yaml."
echo "Register it with: tsh login --proxy=nv-stg-dgxc.teleport.sh && tctl create -f nvcert-token.yaml"

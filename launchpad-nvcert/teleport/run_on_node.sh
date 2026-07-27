#!/usr/bin/env bash
# run_on_node.sh — run this AS ROOT on each nvcert control-plane node.
# Copy install_teleport.sh to /tmp first, then run this.
#
# From bastion:
#   for node in gb300control01 gb300control02 gb300control03; do
#     scp install_teleport.sh $node:/tmp/
#   done
#
# Then on EACH node as root:
#   bash /tmp/run_on_node.sh   (or paste the sudo line below directly)

sudo TELEPORT_SERVER=nv-stg-dgxc.teleport.sh:443 \
     TELEPORT_TOKEN=rg-forge-launchpad-nvcert-nodes-tpm \
     TELEPORT_RESOURCE_GROUP=forge \
     TELEPORT_ENVIRONMENT=non-prod \
     TELEPORT_SITE=launchpad-nvcert \
     bash /tmp/install_teleport.sh

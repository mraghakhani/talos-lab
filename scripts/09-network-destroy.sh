#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh

if ! virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME" >/dev/null 2>&1; then
  log "Network '$LAB_NAME' is not defined; nothing to do"
  exit 0
fi

if virsh -c "$LIBVIRT_URI" list --all --name | grep -q '^talos-'; then
  die "Talos libvirt domains still exist. Destroy VMs before removing their network."
fi

if [[ "$(virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME" | awk '/Active:/ {print $2}')" == "yes" ]]; then
  log "Stopping network '$LAB_NAME'"
  virsh -c "$LIBVIRT_URI" net-destroy "$LAB_NAME" >/dev/null
fi

log "Undefining network '$LAB_NAME'"
virsh -c "$LIBVIRT_URI" net-undefine "$LAB_NAME" >/dev/null
log "Network removed"

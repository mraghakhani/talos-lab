#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh

if ! virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL" >/dev/null 2>&1; then
  log "storage pool '$LIBVIRT_POOL' is not defined; nothing to do"
  exit 0
fi

if virsh -c "$LIBVIRT_URI" list --all --name | grep -q '^talos-'; then
  die "Talos domains still exist. Run task vm:destroy before deleting the pool."
fi

if virsh -c "$LIBVIRT_URI" vol-info --pool "$LIBVIRT_POOL" "$TALOS_ISO_NAME" >/dev/null 2>&1; then
  log "deleting pooled Talos ISO"
  virsh -c "$LIBVIRT_URI" vol-delete --pool "$LIBVIRT_POOL" "$TALOS_ISO_NAME" >/dev/null
fi

state="$(virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL" | awk '/State:/ {print $2}')"
if [[ "$state" == "running" ]]; then
  virsh -c "$LIBVIRT_URI" pool-destroy "$LIBVIRT_POOL" >/dev/null
fi

virsh -c "$LIBVIRT_URI" pool-undefine "$LIBVIRT_POOL" >/dev/null
log "storage pool undefined; cached download under state/downloads is preserved"

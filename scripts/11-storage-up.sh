#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
POOL_XML="$PROJECT_ROOT/state/rendered/pool.xml"
[[ -f "$POOL_XML" ]] || die "missing $POOL_XML; run task storage:render"

if virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL" >/dev/null 2>&1; then
  log "storage pool '$LIBVIRT_POOL' already exists"
else
  log "Defining storage pool '$LIBVIRT_POOL'"
  virsh -c "$LIBVIRT_URI" pool-define "$POOL_XML" >/dev/null
  virsh -c "$LIBVIRT_URI" pool-build "$LIBVIRT_POOL" >/dev/null
fi

virsh -c "$LIBVIRT_URI" pool-autostart "$LIBVIRT_POOL" >/dev/null
if [[ "$(virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL" | awk '/State:/ {print $2}')" != "running" ]]; then
  virsh -c "$LIBVIRT_URI" pool-start "$LIBVIRT_POOL" >/dev/null
fi

virsh -c "$LIBVIRT_URI" pool-refresh "$LIBVIRT_POOL" >/dev/null
virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL"

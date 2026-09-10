#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
NETWORK_XML="$PROJECT_ROOT/state/rendered/network.xml"
[[ -f "$NETWORK_XML" ]] || die "missing $NETWORK_XML; run task network:render"

if virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME" >/dev/null 2>&1; then
  log "libvirt network '$LAB_NAME' already exists"

  current_xml="$(mktemp)"
  trap 'rm -f "$current_xml"' EXIT
  virsh -c "$LIBVIRT_URI" net-dumpxml "$LAB_NAME" > "$current_xml"
  echo "NOTE Network already exists. 'task network:recreate' applies definition changes."
else
  log "Defining libvirt network '$LAB_NAME'"
  virsh -c "$LIBVIRT_URI" net-define "$NETWORK_XML" >/dev/null
fi

log "Enabling network autostart"
virsh -c "$LIBVIRT_URI" net-autostart "$LAB_NAME" >/dev/null

if [[ "$(virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME" | awk '/Active:/ {print $2}')" != "yes" ]]; then
  log "Starting network"
  virsh -c "$LIBVIRT_URI" net-start "$LAB_NAME" >/dev/null
else
  log "Network already active"
fi

virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME"
ip -brief addr show "$LAB_BRIDGE" || true

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
ensure_libvirt_socket virtnetworkd.socket

ensure_ufw_lab_access() {
  if ! systemctl is-active --quiet ufw.service; then
    return
  fi

  need_cmd ufw
  log "Allowing required lab traffic through UFW"
  sudo ufw allow in on "$LAB_BRIDGE" proto udp \
    from 0.0.0.0 port 68 to 255.255.255.255 port 67 \
    comment "$LAB_NAME DHCP" >/dev/null
  sudo ufw route allow in on "$LAB_BRIDGE" proto udp \
    from "$LAB_NETWORK" to any port 123 \
    comment "$LAB_NAME NTP" >/dev/null
  sudo ufw route allow in on "$LAB_BRIDGE" proto tcp \
    from "$LAB_NETWORK" to any port 4460 \
    comment "$LAB_NAME NTS" >/dev/null
}

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

ensure_ufw_lab_access

virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME"
ip -brief addr show "$LAB_BRIDGE" || true

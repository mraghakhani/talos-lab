#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need_cmd virsh

virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME"
echo
virsh -c "$LIBVIRT_URI" net-dhcp-leases "$LAB_NAME" || true
echo
ip route | grep -E '192\.168\.231\.0/24|default' || true

#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need_cmd virsh

virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME"
echo
virsh -c "$LIBVIRT_URI" net-dhcp-leases "$LAB_NAME" || true
echo
ip -brief addr show "$LAB_BRIDGE" || true
echo
ip route show "$LAB_NETWORK" || true
ip route show default || true

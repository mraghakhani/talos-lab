#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
need_cmd yq

printf '%-20s %-13s %-16s %-18s %s\n' NAME ROLE EXPECTED_IP MAC STATE
printf '%-20s %-13s %-16s %-18s %s\n' '--------------------' '-------------' '----------------' '------------------' '-----'

while IFS=$'\t' read -r name role ip mac; do
  if virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    state="$(virsh -c "$LIBVIRT_URI" domstate "$name" | tr -d '\r')"
  else
    state="not-defined"
  fi
  printf '%-20s %-13s %-16s %-18s %s\n' "$name" "$role" "$ip" "$mac" "$state"
done < <(yq -r '.nodes[] | [.name, .role, .ip, .mac] | @tsv' "$PROJECT_ROOT/config/nodes.yaml")

echo
log "DHCP leases"
virsh -c "$LIBVIRT_URI" net-dhcp-leases "$LAB_NAME" || true

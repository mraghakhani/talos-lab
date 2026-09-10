#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
need_cmd yq

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
[[ -s "$NODES_FILE" ]] || die "node inventory missing: $NODES_FILE"

log "HARD power-off requested for all lab VMs"
warn "This is equivalent to pulling the power cable. VM definitions and disks are preserved."

while IFS= read -r name; do
  [[ -n "$name" ]] || continue

  if ! virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    note "$name does not exist; skipping"
    continue
  fi

  state="$(virsh -c "$LIBVIRT_URI" domstate "$name" | tr -d '\r')"

  case "$state" in
    "shut off"|"shutoff"|"crashed")
      note "$name already powered off ($state)"
      ;;
    running|paused|"in shutdown"|pmsuspended|idle)
      log "$name: forcing power off (state: $state)"
      virsh -c "$LIBVIRT_URI" destroy "$name" >/dev/null
      ;;
    *)
      die "$name is in unexpected libvirt state: $state"
      ;;
  esac
done < <(yq -r '.nodes[].name' "$NODES_FILE")

ok "all declared lab VMs are powered off; definitions and disks were preserved"

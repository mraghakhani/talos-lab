#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
need_cmd yq

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"

while IFS= read -r name; do
  [[ -n "$name" ]] || continue

  if ! virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    die "libvirt domain '$name' does not exist"
  fi

  state="$(virsh -c "$LIBVIRT_URI" domstate "$name" | tr -d '\r')"

  case "$state" in
    running)
      note "$name already running"
      ;;
    paused)
      log "$name: resuming"
      virsh -c "$LIBVIRT_URI" resume "$name" >/dev/null
      ;;
    "shut off"|"shutoff")
      log "$name: starting"
      virsh -c "$LIBVIRT_URI" start "$name" >/dev/null
      ;;
    *)
      die "$name is in unexpected libvirt state: $state"
      ;;
  esac
done < <(yq -r '.nodes[].name' "$NODES_FILE")

ok "all lab VMs are running"

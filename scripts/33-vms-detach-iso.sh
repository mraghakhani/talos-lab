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
    note "$name does not exist; skipping"
    continue
  fi

  # Find an attached CD-ROM target. If none is present, this task is idempotent.
  target="$(virsh -c "$LIBVIRT_URI" domblklist "$name" --details | awk '$2 == "cdrom" {print $3; exit}')"
  if [[ -z "$target" ]]; then
    log "$name: no CD-ROM attached"
    continue
  fi

  log "$name: detaching installation ISO from $target"
  virsh -c "$LIBVIRT_URI" change-media "$name" "$target" --eject --config >/dev/null
  # Eject live media too when supported; don't fail if the running domain already sees it ejected.
  virsh -c "$LIBVIRT_URI" change-media "$name" "$target" --eject --live >/dev/null 2>&1 || true
done < <(yq -r '.nodes[].name' "$NODES_FILE")

ok "Talos installation media detached from VM definitions"

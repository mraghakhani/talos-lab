#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
need_cmd yq

# Intentionally targets only names declared in config/nodes.yaml and only their
# explicitly named OS/data volumes. The shared Talos ISO is never deleted here.
while IFS=$'\t' read -r name data_disk; do
  [[ -n "$name" ]] || continue

  if virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    state="$(virsh -c "$LIBVIRT_URI" domstate "$name" | tr -d '\r')"
    if [[ "$state" != "shut off" ]]; then
      log "forcing off $name"
      virsh -c "$LIBVIRT_URI" destroy "$name" >/dev/null || true
    fi

    log "undefining $name"
    virsh -c "$LIBVIRT_URI" undefine "$name" --nvram >/dev/null 2>&1 || \
      virsh -c "$LIBVIRT_URI" undefine "$name" >/dev/null
  else
    log "domain not defined: $name"
  fi

  for volume in "${name}-os.qcow2" "${name}-data.qcow2"; do
    if [[ "$volume" == *-data.qcow2 && "$data_disk" == "0" ]]; then
      continue
    fi
    if virsh -c "$LIBVIRT_URI" vol-info --pool "$LIBVIRT_POOL" "$volume" >/dev/null 2>&1; then
      log "deleting volume $volume"
      virsh -c "$LIBVIRT_URI" vol-delete --pool "$LIBVIRT_POOL" "$volume" >/dev/null
    fi
  done
done < <(yq -r '.nodes[] | [.name, .data_disk_gib] | @tsv' "$PROJECT_ROOT/config/nodes.yaml")

# Warn about lab VMs that are no longer declared in nodes.yaml so the operator
# cleans them up deliberately (this script never deletes undeclared domains).
leftover="$(virsh -c "$LIBVIRT_URI" list --all --name 2>/dev/null | grep -E '^talos-' || true)"
if [[ -n "$leftover" ]]; then
  warn "undeclared talos-* domains still exist in libvirt (not deleted by this script):"
  printf '%s\n' "$leftover"
  warn "undefine them manually if they are leftovers from an earlier topology"
fi

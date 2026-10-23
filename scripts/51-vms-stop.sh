#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Graceful ACPI power-off of every declared lab VM. Waits for each domain to
# reach "shut off" and refuses to escalate: if a VM does not stop cleanly the
# operator decides whether to use task vm:stop:force.
#
# vm:stop:force stays the explicit destructive escape hatch.

need_cmd virsh
need_cmd yq
need_cmd talosctl

STOP_TIMEOUT_SECONDS="${VM_STOP_TIMEOUT:-120}"
API_SHUTDOWN_GRACE_SECONDS="${VM_STOP_API_GRACE:-30}"
[[ -s "$NODES_FILE" ]] || die "node inventory missing: $NODES_FILE"

log "graceful shutdown requested for all lab VMs (grace ${API_SHUTDOWN_GRACE_SECONDS}s API + timeout ${STOP_TIMEOUT_SECONDS}s ACPI)"

# All guests in this lab are Talos nodes; the Talos API shutdown is the most
# reliable graceful channel. ACPI power-button is the fallback for a node
# whose API is already unreachable.
#
# --force --wait=false is deliberate:
#   - --wait (the default) blocks until the sequence finishes and gets killed
#     by the timeout wrapper mid-sequence, leaving the guest half-shut-down.
#   - cordon/drain (skipped by --force) cannot complete on a node without a
#     bootstrapped cluster and hangs the shutdown sequence. The shutdown is
#     still clean at the OS level (services stop, filesystems sync).
node_ip() {
  yq -r ".nodes[] | select(.name == \"$1\") | .ip" "$NODES_FILE"
}

talos_api_shutdown() {
  local name="$1" ip
  [[ -s "$TALOSCONFIG" ]] || return 1
  ip="$(node_ip "$name")"
  [[ -n "$ip" ]] || return 1
  timeout 10s talosctl --talosconfig "$TALOSCONFIG" \
    --endpoints "$ip" --nodes "$ip" shutdown --force --wait=false >/dev/null 2>&1
}

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
      continue
      ;;
    running|"in shutdown")
      if talos_api_shutdown "$name"; then
        log "$name: Talos API shutdown sent"
      else
        log "$name: Talos API unavailable; falling back to ACPI shutdown"
        virsh -c "$LIBVIRT_URI" shutdown "$name" >/dev/null
      fi
      ;;
    paused)
      log "$name: resuming, then ACPI shutdown"
      virsh -c "$LIBVIRT_URI" resume "$name" >/dev/null
      virsh -c "$LIBVIRT_URI" shutdown "$name" >/dev/null
      ;;
    *)
      die "$name is in unexpected libvirt state: $state"
      ;;
  esac

  waited=0
  while true; do
    state="$(virsh -c "$LIBVIRT_URI" domstate "$name" | tr -d '\r')"
    case "$state" in
      "shut off"|"shutoff")
        ok "$name powered off"
        break
        ;;
      crashed)
        die "$name crashed while shutting down"
        ;;
      *)
        if (( waited >= STOP_TIMEOUT_SECONDS )); then
          die "$name did not power off within ${STOP_TIMEOUT_SECONDS}s (state: $state). Investigate the guest, then decide on 'task vm:stop:force'."
        fi
        sleep 2
        waited=$((waited + 2))
        ;;
    esac
  done
done < <(yq -r '.nodes[].name' "$NODES_FILE")

ok "all declared lab VMs are powered off cleanly"

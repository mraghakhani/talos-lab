#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need_cmd talosctl

log "Configured old cluster name: $OLD_CLUSTER_NAME"
log "User cluster state"
find "$HOME/.talos/clusters" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true

log "talosctl cluster show (QEMU provisioner)"
talosctl cluster show --name "$OLD_CLUSTER_NAME" --provisioner qemu 2>/dev/null || true

log "QEMU/Talos processes"
pgrep -af 'qemu-system|talos' || true

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl

STATE_DIR="$HOME/.talos/clusters/$OLD_CLUSTER_NAME"

if [[ ! -d "$STATE_DIR" ]]; then
  warn "No state directory at $STATE_DIR. Nothing destroyed."
  warn "If your previous cluster had another name, change OLD_CLUSTER_NAME in config/lab.env after running discovery."
  exit 0
fi

log "Destroying talosctl-managed QEMU cluster '$OLD_CLUSTER_NAME'"
log "State directory: $STATE_DIR"
sudo --preserve-env=HOME talosctl cluster destroy --name "$OLD_CLUSTER_NAME"

if [[ -d "$STATE_DIR" ]]; then
  die "cluster destroy returned but $STATE_DIR still exists; inspect before using --force"
fi

log "Old QEMU cluster destroyed"

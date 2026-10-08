#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
SNAPSHOT_DIR="$PROJECT_ROOT/state/etcd-snapshots"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing"

cp_ip="$(yq -r '[.nodes[] | select(.role == "controlplane") | .ip][0]' "$NODES_FILE")"
[[ -n "$cp_ip" && "$cp_ip" != "null" ]] || die "no control-plane node found"

mkdir -p "$SNAPSHOT_DIR"
snapshot_file="$SNAPSHOT_DIR/etcd-snapshot-$(date -u +%Y%m%dT%H%M%SZ).snapshot"

log "Taking etcd snapshot from $cp_ip (direct node check)"
# -n and -e are the same node: avoid another control plane proxying the request.
talosctl --talosconfig "$TALOSCONFIG" -n "$cp_ip" -e "$cp_ip" etcd snapshot "$snapshot_file"

[[ -s "$snapshot_file" ]] || die "snapshot file missing or empty: $snapshot_file"
ok "etcd snapshot saved: $snapshot_file ($(du -h "$snapshot_file" | cut -f1))"

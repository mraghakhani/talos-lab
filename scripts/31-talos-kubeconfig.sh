#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
KUBECONFIG="$GENERATED/kubeconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
cp_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE" | head -n1)"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"

log "retrieving admin kubeconfig through Talos API on $cp_ip"
talosctl --talosconfig "$TALOSCONFIG" --nodes "$cp_ip" kubeconfig "$KUBECONFIG" --merge=false --force
chmod 600 "$KUBECONFIG"
ok "wrote ${KUBECONFIG#"$PROJECT_ROOT"/}"
echo "Use: export KUBECONFIG=$KUBECONFIG"

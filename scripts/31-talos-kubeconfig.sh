#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

cp_ip="$(yq -r '[.nodes[] | select(.role == "controlplane") | .ip][0]' "$NODES_FILE")"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"

log "retrieving admin kubeconfig through Talos API on $cp_ip"
talosctl --talosconfig "$TALOSCONFIG" --nodes "$cp_ip" kubeconfig "$KUBECONFIG" --merge=false --force
chmod 600 "$KUBECONFIG"
ok "wrote ${KUBECONFIG#"$PROJECT_ROOT"/}"
echo "Use: export KUBECONFIG=$KUBECONFIG"

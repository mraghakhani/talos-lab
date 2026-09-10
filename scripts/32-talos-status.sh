#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd kubectl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
KUBECONFIG="$GENERATED/kubeconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
cp_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE" | head -n1)"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing"

log "Talos cluster members"
talosctl --talosconfig "$TALOSCONFIG" --nodes "$cp_ip" get members || true

echo
log "etcd members"
talosctl --talosconfig "$TALOSCONFIG" --nodes "$cp_ip" etcd members || true

echo
log "Kubernetes nodes"
if [[ -s "$KUBECONFIG" ]]; then
  kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide || true
else
  note "kubeconfig not generated yet; run task talos:kubeconfig after bootstrap"
fi

echo
note "Nodes are expected to remain NotReady until Cilium is installed; default CNI and kube-proxy are intentionally disabled."

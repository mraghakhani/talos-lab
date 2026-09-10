#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd kubectl
need_cmd talosctl
need_cmd timeout
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
KUBECONFIG="$GENERATED/kubeconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
PENDING_MARKER="$GENERATED/.bootstrap-requested"
COMPLETE_MARKER="$GENERATED/.bootstrap-complete"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing"

cp_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE" | head -n1)"
[[ -n "$cp_ip" && "$cp_ip" != null ]] || die "no control-plane node found"

talos_direct=(talosctl --talosconfig "$TALOSCONFIG" --endpoints "$cp_ip" --nodes "$cp_ip")

if [[ -e "$COMPLETE_MARKER" ]]; then
  note "bootstrap marker: completed"
elif [[ -e "$PENDING_MARKER" ]]; then
  warn "bootstrap marker: request was started but completion was not recorded"
else
  note "bootstrap marker: no bootstrap request recorded"
fi

echo
log "Talos cluster members"
if ! timeout 10s "${talos_direct[@]}" get members; then
  warn "Talos member query timed out or failed"
fi

echo
log "etcd service on bootstrap node"
if ! timeout 10s "${talos_direct[@]}" service etcd; then
  warn "etcd service query timed out or failed"
fi

echo
log "etcd members"
if ! timeout 10s "${talos_direct[@]}" etcd members; then
  note "etcd membership is not available yet"
fi

echo
log "Kubernetes nodes"
if [[ -s "$KUBECONFIG" ]]; then
  if ! timeout 10s kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide; then
    note "Kubernetes API is not available yet"
  fi
else
  note "kubeconfig not generated yet; run task talos:kubeconfig after bootstrap"
fi

echo
note "Nodes may remain NotReady until Cilium is installed; default CNI and kube-proxy are intentionally disabled."

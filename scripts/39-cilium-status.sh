#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd kubectl
need_cmd cilium-cli

KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"
[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"

export KUBECONFIG

log "Cilium status"
cilium-cli status --wait --wait-duration 5m

echo
log "Kubernetes nodes"
kubectl get nodes -o wide

echo
log "kube-system networking pods"
kubectl -n kube-system get pods -o wide

not_ready="$(
  kubectl get nodes --no-headers |
    awk '$2 != "Ready" {print $1}'
)"

if [[ -n "$not_ready" ]]; then
  printf '%s\n' "$not_ready" >&2
  die "one or more Kubernetes nodes are still NotReady"
fi

ok "Cilium is healthy and all Kubernetes nodes are Ready"

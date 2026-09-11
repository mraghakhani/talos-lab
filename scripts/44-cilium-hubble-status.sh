#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd cilium-cli
need_cmd kubectl

KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"
[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"

export KUBECONFIG

log "Cilium/Hubble deployment status"
cilium-cli status

echo
log "Hubble Relay pods"
kubectl -n kube-system get pods -l k8s-app=hubble-relay -o wide

echo
log "Hubble UI pods"
kubectl -n kube-system get pods -l k8s-app=hubble-ui -o wide

ok "Hubble deployment objects inspected"

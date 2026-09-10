#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd helm
need_cmd kubectl
need_cmd yq

VERSIONS="$PROJECT_ROOT/config/versions.yaml"
VALUES="$PROJECT_ROOT/platform/cilium/values.yaml"
KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"

[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"
[[ -s "$VALUES" ]] || die "Cilium values missing: $VALUES"

CILIUM_VERSION="$(yq -r '.platform.cilium // ""' "$VERSIONS")"
[[ -n "$CILIUM_VERSION" ]] || die "platform.cilium is not pinned in config/versions.yaml"

HOST_PROXY="${PROXY_SCHEME}://127.0.0.1:${PROXY_PORT}"

log "installing/upgrading Cilium $CILIUM_VERSION"
HTTP_PROXY="$HOST_PROXY" HTTPS_PROXY="$HOST_PROXY" \
NO_PROXY="localhost,127.0.0.1,${LAB_NETWORK},${K8S_API_VIP}" \
  helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
    --version "$CILIUM_VERSION" \
    --namespace kube-system \
    --values "$VALUES" \
    --kubeconfig "$KUBECONFIG" \
    --wait \
    --timeout 10m

ok "Cilium Helm release applied"

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Install the Kubernetes Gateway API CRDs (standard channel) pinned to the
# version documented for the running Cilium release. Idempotent: safe to re-run.
# Reference: https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/

need_cmd kubectl
need_cmd yq

VERSIONS="$PROJECT_ROOT/config/versions.yaml"
KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"
HOST_PROXY="${PROXY_SCHEME}://127.0.0.1:${PROXY_PORT}"

[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"

GATEWAY_API_VERSION="$(yq -r '.platform.gateway_api // ""' "$VERSIONS")"
[[ -n "$GATEWAY_API_VERSION" ]] || die "platform.gateway_api is not pinned in config/versions.yaml"

BASE_URL="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GATEWAY_API_VERSION}/config/crd/standard"
CRDS=(
  gateway.networking.k8s.io_gatewayclasses.yaml
  gateway.networking.k8s.io_gateways.yaml
  gateway.networking.k8s.io_httproutes.yaml
  gateway.networking.k8s.io_referencegrants.yaml
  gateway.networking.k8s.io_grpcroutes.yaml
  gateway.networking.k8s.io_backendtlspolicies.yaml
  gateway.networking.k8s.io_tlsroutes.yaml
)

log "Installing Gateway API CRDs (standard channel, ${GATEWAY_API_VERSION})"
for crd in "${CRDS[@]}"; do
  HTTPS_PROXY="$HOST_PROXY" NO_PROXY="localhost,127.0.0.1,${LAB_NETWORK},${K8S_API_VIP}" \
    kubectl apply --server-side --force-conflicts \
      --kubeconfig "$KUBECONFIG" \
      -f "${BASE_URL}/${crd}"
done

installed="$(kubectl --kubeconfig "$KUBECONFIG" get crd -o name | grep -c 'gateway.networking.k8s.io' || true)"
[[ "$installed" -ge "${#CRDS[@]}" ]] \
  || die "expected at least ${#CRDS[@]} gateway CRDs, found $installed"
ok "Gateway API CRDs installed ($installed CRDs, ${GATEWAY_API_VERSION})"

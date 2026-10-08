#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd helm
need_cmd kubectl
need_cmd yq

VERSIONS="$PROJECT_ROOT/config/versions.yaml"
VALUES="$PROJECT_ROOT/platform/cert-manager/values.yaml"
KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"

[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"
[[ -s "$VALUES" ]] || die "cert-manager values missing: $VALUES"

CERT_MANAGER_VERSION="$(yq -r '.platform.cert_manager // ""' "$VERSIONS")"
[[ -n "$CERT_MANAGER_VERSION" ]] || die "platform.cert_manager is not pinned in config/versions.yaml"

HOST_PROXY="${PROXY_SCHEME}://127.0.0.1:${PROXY_PORT}"

log "refreshing jetstack Helm repository"
HTTP_PROXY="$HOST_PROXY" HTTPS_PROXY="$HOST_PROXY" \
NO_PROXY="localhost,127.0.0.1,${LAB_NETWORK},${K8S_API_VIP}" \
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
HTTP_PROXY="$HOST_PROXY" HTTPS_PROXY="$HOST_PROXY" \
NO_PROXY="localhost,127.0.0.1,${LAB_NETWORK},${K8S_API_VIP}" \
  helm repo update jetstack >/dev/null

log "installing/upgrading cert-manager $CERT_MANAGER_VERSION"
HTTP_PROXY="$HOST_PROXY" HTTPS_PROXY="$HOST_PROXY" \
NO_PROXY="localhost,127.0.0.1,${LAB_NETWORK},${K8S_API_VIP}" \
  helm upgrade --install cert-manager jetstack/cert-manager \
    --version "$CERT_MANAGER_VERSION" \
    --namespace cert-manager --create-namespace \
    --values "$VALUES" \
    --kubeconfig "$KUBECONFIG" \
    --wait \
    --timeout 10m

ok "cert-manager Helm release applied"
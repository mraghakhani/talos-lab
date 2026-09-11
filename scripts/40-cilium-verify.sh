#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd cilium-cli

KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"
[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"

export KUBECONFIG

log "cleaning stale Cilium connectivity-test resources"
cilium-cli connectivity test --cleanup >/dev/null 2>&1 || true

log "running proxy-aware Cilium core connectivity suite"
note "Direct pod-to-Internet scenarios are excluded by design; Talos nodes use the host proxy, pods do not."

cilium-cli connectivity test \
  --namespace-labels pod-security.kubernetes.io/enforce=privileged \
  --namespace-labels pod-security.kubernetes.io/warn=privileged \
  --namespace-labels pod-security.kubernetes.io/audit=privileged \
  --test '!/pod-to-world' \
  --test '!/pod-to-cidr' \
  --hubble=false \
  --timeout 15m

ok "Cilium core connectivity suite completed"

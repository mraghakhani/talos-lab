#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd cilium-cli
need_cmd sleep

KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"
[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"

export KUBECONFIG

log "cleaning stale Cilium connectivity-test resources"
cilium-cli connectivity test --cleanup >/dev/null 2>&1 || true

log "starting Hubble Relay port-forward on 127.0.0.1:4245"
cilium-cli hubble port-forward >/tmp/talos-lab-hubble-port-forward.log 2>&1 &
hubble_pf_pid=$!

cleanup() {
  if kill -0 "$hubble_pf_pid" >/dev/null 2>&1; then
    kill "$hubble_pf_pid" >/dev/null 2>&1 || true
    wait "$hubble_pf_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

sleep 2

if ! kill -0 "$hubble_pf_pid" >/dev/null 2>&1; then
  cat /tmp/talos-lab-hubble-port-forward.log >&2 || true
  die "Hubble Relay port-forward exited unexpectedly"
fi

log "running full upstream Cilium connectivity suite"
warn "This suite expects direct pod Internet access; it may fail in this proxy-constrained lab."

cilium-cli connectivity test \
  --namespace-labels pod-security.kubernetes.io/enforce=privileged \
  --namespace-labels pod-security.kubernetes.io/warn=privileged \
  --namespace-labels pod-security.kubernetes.io/audit=privileged \
  --timeout 30m \
  --flow-validation warning

ok "full Cilium connectivity suite completed"

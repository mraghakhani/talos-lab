#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd cilium-cli

[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"

export KUBECONFIG

log "cleaning Cilium connectivity-test artifacts"
cilium-cli connectivity test --cleanup
ok "Cilium connectivity-test artifacts cleaned"

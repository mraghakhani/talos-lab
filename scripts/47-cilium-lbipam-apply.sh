#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Render the Cilium LB-IPAM pool and L2 announcement policy from lab.env
# values and apply them idempotently. Requires Cilium >= 1.14 with
# l2announcements.enabled=true (platform/cilium/values.yaml).

need_cmd envsubst
need_cmd kubectl

TEMPLATE="$PROJECT_ROOT/platform/cilium/lb-ipam.yaml.tmpl"
KUBECONFIG="$PROJECT_ROOT/infrastructure/talos/generated/kubeconfig"
OUT_DIR="$PROJECT_ROOT/state/rendered"
OUT="$OUT_DIR/cilium-lb-ipam.yaml"

[[ -s "$TEMPLATE" ]] || die "template missing: $TEMPLATE"
[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"
[[ -n "${CILIUM_LB_START:-}" ]] || die "CILIUM_LB_START not set in lab.env"
[[ -n "${CILIUM_LB_END:-}" ]] || die "CILIUM_LB_END not set in lab.env"
[[ -n "${CILIUM_LB_INTERFACE:-}" ]] || die "CILIUM_LB_INTERFACE not set in lab.env"

mkdir -p "$OUT_DIR"
export CILIUM_LB_START CILIUM_LB_END CILIUM_LB_INTERFACE
envsubst < "$TEMPLATE" > "$OUT"
log "rendered $OUT"

export KUBECONFIG
kubectl apply -f "$OUT"

# Cilium 1.20 pool status publishes PoolConflict/IPs* conditions (no Init).
# A usable pool has no conflict and at least one available IP.
conflict="$(kubectl get ciliumloadbalancerippool.cilium.io lab-lb-pool \
  -o jsonpath='{.status.conditions[?(@.type=="cilium.io/PoolConflict")].status}')"
available="$(kubectl get ciliumloadbalancerippool.cilium.io lab-lb-pool \
  -o jsonpath='{.status.conditions[?(@.type=="cilium.io/IPsAvailable")].message}')"
[[ "$conflict" == "False" ]] || die "pool reports PoolConflict=$conflict"
[[ -n "$available" && "$available" != "0" ]] || die "pool has no available IPs"

ok "CiliumLoadBalancerIPPool lab-lb-pool (${CILIUM_LB_START}-${CILIUM_LB_END}) and CiliumL2AnnouncementPolicy lab-l2-policy applied"

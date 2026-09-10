#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"
bootstrap_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE" | head -n1)"
[[ -n "$bootstrap_ip" && "$bootstrap_ip" != null ]] || die "no control-plane node found"

if talosctl --talosconfig "$TALOSCONFIG" --nodes "$bootstrap_ip" etcd members >/dev/null 2>&1; then
  ok "etcd already appears bootstrapped; refusing to bootstrap twice"
  exit 0
fi

log "bootstrapping etcd/Kubernetes from $bootstrap_ip"
talosctl --talosconfig "$TALOSCONFIG" --nodes "$bootstrap_ip" bootstrap
ok "bootstrap request completed"
note "The Layer-2 VIP ${K8S_API_VIP} becomes available only after etcd/API health permits VIP election."

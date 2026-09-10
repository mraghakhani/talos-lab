#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd timeout
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
PENDING_MARKER="$GENERATED/.bootstrap-requested"
COMPLETE_MARKER="$GENERATED/.bootstrap-complete"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"

bootstrap_ip="$(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE" | head -n1)"
[[ -n "$bootstrap_ip" && "$bootstrap_ip" != null ]] || die "no control-plane node found"

if [[ -e "$COMPLETE_MARKER" ]]; then
  ok "bootstrap already completed according to local state marker"
  exit 0
fi

if [[ -e "$PENDING_MARKER" ]]; then
  die "a previous bootstrap request may already have been sent. Refusing to retry automatically. Inspect etcd/control-plane state first."
fi

log "verifying direct Talos API access to bootstrap node $bootstrap_ip"
if ! timeout 10s talosctl \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$bootstrap_ip" \
  --nodes "$bootstrap_ip" \
  version >/dev/null; then
  die "cannot reach bootstrap node directly through Talos API"
fi

log "bootstrapping etcd/Kubernetes exactly once from $bootstrap_ip"
printf 'requested_at=%s\nbootstrap_ip=%s\n' "$(date --iso-8601=seconds)" "$bootstrap_ip" >"$PENDING_MARKER"

if talosctl \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$bootstrap_ip" \
  --nodes "$bootstrap_ip" \
  bootstrap; then
  mv "$PENDING_MARKER" "$COMPLETE_MARKER"
  ok "bootstrap request completed"
  note "The Layer-2 VIP ${K8S_API_VIP} becomes available after etcd/API health permits VIP election."
else
  warn "bootstrap command returned an error or was interrupted"
  die "bootstrap attempt is recorded in $PENDING_MARKER. Do NOT retry automatically; inspect status first."
fi

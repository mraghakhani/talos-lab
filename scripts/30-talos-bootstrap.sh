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

mapfile -t node_ips < <(yq -r '.nodes[].ip' "$NODES_FILE")
mapfile -t control_plane_ips < <(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE")
((${#node_ips[@]} > 0)) || die "no nodes found"
((${#control_plane_ips[@]} > 0)) || die "no control-plane node found"
bootstrap_ip="${control_plane_ips[0]}"

talos_direct() {
  local ip="$1"
  shift

  talosctl \
    --talosconfig "$TALOSCONFIG" \
    --endpoints "$ip" \
    --nodes "$ip" \
    "$@"
}

talos_direct_timeout() {
  local duration="$1"
  local ip="$2"
  shift 2

  timeout "$duration" talosctl \
    --talosconfig "$TALOSCONFIG" \
    --endpoints "$ip" \
    --nodes "$ip" \
    "$@"
}

find_initialized_control_plane() {
  local ip

  for ip in "${control_plane_ips[@]}"; do
    if talos_direct_timeout 5s "$ip" etcd members >/dev/null 2>&1; then
      printf '%s\n' "$ip"
      return 0
    fi
  done

  return 1
}

mark_bootstrap_complete() {
  local etcd_ip="$1"

  rm -f "$PENDING_MARKER"
  printf 'verified_at=%s\netcd_ip=%s\n' \
    "$(date --iso-8601=seconds)" \
    "$etcd_ip" >"$COMPLETE_MARKER"
}

log "verifying direct Talos API access to every node"
for ip in "${node_ips[@]}"; do
  if ! talos_direct_timeout 10s "$ip" version >/dev/null; then
    die "cannot reach $ip directly through Talos API"
  fi
done

if initialized_ip="$(find_initialized_control_plane)"; then
  mark_bootstrap_complete "$initialized_ip"
  ok "etcd is already initialized and reachable through $initialized_ip; bootstrap not repeated"
  exit 0
fi

log "verifying that no control-plane node has an existing etcd data directory"
for ip in "${control_plane_ips[@]}"; do
  if etcd_data_check="$(talos_direct_timeout 10s "$ip" list /var/lib/etcd/member 2>&1)"; then
    die "etcd data exists on $ip while membership is unavailable; refusing to bootstrap"
  fi

  if [[ "$etcd_data_check" != *"no such file or directory"* ]]; then
    printf '%s\n' "$etcd_data_check" >&2
    die "could not prove that etcd is uninitialized on $ip; refusing to bootstrap"
  fi
done

if [[ -e "$PENDING_MARKER" ]]; then
  die "a previous bootstrap request may already have been sent. Refusing to retry automatically. Inspect etcd/control-plane state first."
fi

if [[ -e "$COMPLETE_MARKER" ]]; then
  warn "removing stale bootstrap-complete marker after proving etcd is uninitialized on every control plane"
  rm -f "$COMPLETE_MARKER"
fi

log "bootstrapping etcd/Kubernetes exactly once from $bootstrap_ip"
printf 'requested_at=%s\nbootstrap_ip=%s\n' "$(date --iso-8601=seconds)" "$bootstrap_ip" >"$PENDING_MARKER"

bootstrap_request_succeeded=false
if talos_direct "$bootstrap_ip" bootstrap; then
  bootstrap_request_succeeded=true
else
  warn "bootstrap command returned an error or was interrupted; checking actual etcd state before failing"
fi

log "waiting for verified etcd membership"
for _ in $(seq 1 24); do
  if initialized_ip="$(find_initialized_control_plane)"; then
    mark_bootstrap_complete "$initialized_ip"
    ok "etcd bootstrap verified through $initialized_ip"
    note "The Layer-2 VIP ${K8S_API_VIP} becomes available after etcd/API health permits VIP election."
    exit 0
  fi

  sleep 2
done

if [[ "$bootstrap_request_succeeded" == true ]]; then
  die "bootstrap request returned successfully, but etcd membership was not verified. Request remains recorded in $PENDING_MARKER; do NOT retry automatically."
fi

die "bootstrap request failed and etcd membership was not verified. Request remains recorded in $PENDING_MARKER; do NOT retry automatically."

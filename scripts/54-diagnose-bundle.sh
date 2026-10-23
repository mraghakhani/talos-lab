#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Collect a read-only diagnostic bundle under state/diagnostics/<timestamp>/.
#
# Contents (each step optional; a partially built lab still produces a bundle):
#   talos-version.txt  talosctl client/server versions
#   k8s-version.txt    kubectl version
#   vm-status.txt      VM state, DHCP leases, volume allocation (scripts/14)
#   talos-status.txt   Talos API + cluster status (scripts/32)
#   talos-<node>.txt   per-node machined service status
#   dmesg.txt          per-node kernel/machined log tails (scripts/52)
#   etcd.txt           etcd members and alarms per control-plane node
#   health.txt         talosctl cluster health
#   k8s.txt            Kubernetes nodes, pods, events (scripts/53)
#   cilium.txt         Cilium status (if the cilium CLI is installed)
#
# No secrets: only read-only status output is collected. The bundle is scanned
# for key/certificate material at the end and any hit is deleted and reported.

need_cmd yq

OUT_DIR="$PROJECT_ROOT/state/diagnostics/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

run_capture() {
  local file="$1"
  shift
  if ! "$@" >"$OUT_DIR/$file" 2>&1; then
    echo "[command failed: $*]" >>"$OUT_DIR/$file"
  fi
}

log "Writing diagnostic bundle to $OUT_DIR"

cp_ip="$(yq -r '[.nodes[] | select(.role == "controlplane")][0].ip' "$NODES_FILE")"
run_capture talos-version.txt talosctl --talosconfig "$TALOSCONFIG" --endpoints "$cp_ip" --nodes "$cp_ip" version --short
run_capture k8s-version.txt kubectl version
run_capture vm-status.txt "$PROJECT_ROOT/scripts/14-vms-status.sh"
run_capture talos-status.txt "$PROJECT_ROOT/scripts/32-talos-status.sh"
run_capture dmesg.txt "$PROJECT_ROOT/scripts/52-talos-dmesg.sh"
run_capture k8s.txt "$PROJECT_ROOT/scripts/53-cluster-status.sh"

while IFS=$'\t' read -r name ip; do
  [[ -n "$name" ]] || continue
  if [[ -s "$TALOSCONFIG" ]]; then
    direct=(talosctl --talosconfig "$TALOSCONFIG" --endpoints "$ip" --nodes "$ip")
  else
    direct=(talosctl --insecure --nodes "$ip")
  fi
  run_capture "talos-$name.txt" "${direct[@]}" services
  run_capture "etcd-members-$name.txt" "${direct[@]}" etcd members
  run_capture "etcd-alarms-$name.txt" "${direct[@]}" etcd alarm list
done < <(yq -r '.nodes[] | select(.role == "controlplane") | [.name, .ip] | @tsv' "$NODES_FILE")

run_capture health.txt timeout 120s talosctl --talosconfig "$TALOSCONFIG" health
if command -v cilium >/dev/null 2>&1 && [[ -s "$KUBECONFIG" ]]; then
  run_capture cilium.txt cilium status
fi

# Secret guard: nothing above should emit key material; prove it.
leaks="$(grep -rlE 'PRIVATE KEY|BEGIN CERTIFICATE|BEGIN OPENSSH' "$OUT_DIR" || true)"
if [[ -n "$leaks" ]]; then
  while read -r f; do
    [[ -n "$f" ]] || continue
    rm -f "$f"
    warn "removed $f (contained key/certificate material)"
  done <<<"$leaks"
fi

ok "diagnostic bundle written to $OUT_DIR"

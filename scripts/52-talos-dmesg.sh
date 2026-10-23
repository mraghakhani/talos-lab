#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Print Talos kernel/machined logs straight from each node over a direct Talos
# API connection (AGENTS.md: use the target node as both --endpoints and --nodes).
#
# Usage:
#   52-talos-dmesg.sh                  tail of the log on every node
#   52-talos-dmesg.sh talos-node-02    one node (name or IP)
#   52-talos-dmesg.sh 192.168.231.11 install
#                                      one node + case-insensitive filter
#
# Works for installed nodes (mTLS) and maintenance-mode nodes (insecure), so it
# is usable before, during and after the first install. The install-time
# "pulling image ..." progress lines are what tell you an install is still
# downloading on a slow link.

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
TAIL_LINES="${TALOS_DMESG_TAIL:-40}"

selector="${1:-}"
filter="${2:-}"
matched=0

while IFS=$'\t' read -r name ip; do
  [[ -n "$name" ]] || continue
  if [[ -n "$selector" && "$selector" != "$name" && "$selector" != "$ip" ]]; then
    continue
  fi
  matched=1

  auth_flags=()
  if [[ -s "$TALOSCONFIG" ]]; then
    auth_flags=(--talosconfig "$TALOSCONFIG")
  fi
  if ! out="$(talosctl "${auth_flags[@]}" --endpoints "$ip" --nodes "$ip" dmesg 2>/dev/null)"; then
    out="$(talosctl dmesg --insecure --nodes "$ip" 2>&1 || true)"
  fi

  echo "=== $name ($ip)"
  if [[ -n "$filter" ]]; then
    printf '%s\n' "$out" | grep -i -F -- "$filter" | tail -n "$TAIL_LINES" || true
  else
    printf '%s\n' "$out" | tail -n "$TAIL_LINES"
  fi
done < <(yq -r '.nodes[] | [.name, .ip] | @tsv' "$NODES_FILE")

if [[ "$matched" -eq 0 ]]; then
  die "no node matched '$selector' in $NODES_FILE"
fi

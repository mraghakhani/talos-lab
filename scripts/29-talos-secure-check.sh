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

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"

printf '%-20s %-15s %-10s %-10s\n' "NAME" "IP" "API" "HOSTNAME"
printf '%-20s %-15s %-10s %-10s\n' "--------------------" "---------------" "----------" "----------"

failures=0

while IFS=$'\t' read -r name ip; do
  [[ -n "$name" && -n "$ip" ]] || continue

  api_status="FAIL"
  hostname_status="FAIL"

  talos_direct=(
    talosctl
    --talosconfig "$TALOSCONFIG"
    --endpoints "$ip"
    --nodes "$ip"
  )

  if timeout 8s "${talos_direct[@]}" version >/dev/null 2>&1; then
    api_status="OK"

    if hostname_out="$(timeout 8s "${talos_direct[@]}" get hostname 2>/dev/null)" \
      && grep -Fq "$name" <<<"$hostname_out"; then
      hostname_status="OK"
    fi
  fi

  printf '%-20s %-15s %-10s %-10s\n' \
    "$name" "$ip" "$api_status" "$hostname_status"

  if [[ "$api_status" != "OK" || "$hostname_status" != "OK" ]]; then
    failures=$((failures + 1))
  fi
done < <(yq -r '.nodes[] | [.name, .ip] | @tsv' "$NODES_FILE")

if (( failures > 0 )); then
  die "$failures post-install Talos checks failed"
fi

ok "all nodes are directly reachable with mTLS and have expected hostnames"

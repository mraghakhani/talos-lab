#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
TALOS_VERSION="$(yq -r '.cluster.talos' "$PROJECT_ROOT/config/versions.yaml")"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"
failures=0

printf '%-20s %-15s %-10s %-10s\n' NAME IP API HOSTNAME
printf '%-20s %-15s %-10s %-10s\n' -------------------- --------------- ---------- ----------

while IFS=$'\t' read -r name ip; do
  [[ -n "$name" ]] || continue
  api=FAIL
  hostname=FAIL

  out="$(talosctl --talosconfig "$TALOSCONFIG" --nodes "$ip" version --short 2>&1 || true)"
  if grep -q "$TALOS_VERSION" <<<"$out"; then
    api=OK
  else
    ((failures+=1))
  fi

  host_out="$(talosctl --talosconfig "$TALOSCONFIG" --nodes "$ip" get hostname 2>&1 || true)"
  if grep -q "$name" <<<"$host_out"; then
    hostname=OK
  else
    ((failures+=1))
  fi

  printf '%-20s %-15s %-10s %-10s\n' "$name" "$ip" "$api" "$hostname"
done < <(yq -r '.nodes[] | [.name, .ip] | @tsv' "$NODES_FILE")

(( failures == 0 )) || die "$failures post-install Talos checks failed; nodes may still be rebooting"
ok "all nodes are installed, reachable with mTLS, and have expected hostnames"

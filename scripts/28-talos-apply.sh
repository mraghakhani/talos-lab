#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"

while IFS=$'\t' read -r name role ip; do
  [[ -n "$name" ]] || continue
  cfg="$GENERATED/${name}.yaml"
  [[ -s "$cfg" ]] || die "missing config for $name; run task talos:generate"

  log "applying initial Talos config to $name ($role, $ip)"
  talosctl apply-config \
    --insecure \
    --nodes "$ip" \
    --file "$cfg"
done < <(yq -r '.nodes[] | [.name, .role, .ip] | @tsv' "$NODES_FILE")

ok "initial machine configurations submitted; nodes will install to $TALOS_INSTALL_DISK and reboot"
note "Do not bootstrap until 'task talos:secure:check' succeeds for all six nodes."

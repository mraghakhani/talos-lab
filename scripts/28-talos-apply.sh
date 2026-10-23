#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
APPLY_ATTEMPTS="${TALOS_APPLY_ATTEMPTS:-5}"
APPLY_RETRY_DELAY="${TALOS_APPLY_RETRY_DELAY:-15}"

while IFS=$'\t' read -r name role ip; do
  [[ -n "$name" ]] || continue
  cfg="$GENERATED/${name}.yaml"
  [[ -s "$cfg" ]] || die "missing config for $name; run task talos:generate"

  log "applying Talos config to $name ($role, $ip)"
  # --mode=auto is required for the first install: from maintenance mode it
  # triggers talos install to $TALOS_INSTALL_DISK and a reboot. --mode=staged
  # only persists config and never installs, so nodes would stay in
  # maintenance mode forever. Retries absorb transient failures on slow links.
  #
  # Maintenance nodes serve only the insecure API; installed nodes serve only
  # the authenticated one. Probe once, then apply through the right channel.
  auth_flags=(--insecure)
  if ! talosctl version --insecure --nodes "$ip" >/dev/null 2>&1; then
    [[ -s "$TALOSCONFIG" ]] || die "$name is not in maintenance mode and talosconfig is missing; run task talos:generate"
    auth_flags=(--talosconfig "$TALOSCONFIG")
  fi
  applied=false
  for attempt in $(seq 1 "$APPLY_ATTEMPTS"); do
    if talosctl apply-config \
      "${auth_flags[@]}" \
      --nodes "$ip" \
      --file "$cfg" \
      --mode=auto; then
      applied=true
      break
    fi
    warn "apply to $name failed (attempt $attempt/$APPLY_ATTEMPTS); retrying in ${APPLY_RETRY_DELAY}s"
    sleep "$APPLY_RETRY_DELAY"
  done
  if [[ "$applied" != true ]]; then
    die "could not apply machine config to $name after $APPLY_ATTEMPTS attempts"
  fi
done < <(yq -r '.nodes[] | [.name, .role, .ip] | @tsv' "$NODES_FILE")

ok "initial machine configurations submitted; nodes will install to $TALOS_INSTALL_DISK and reboot"
note "Do not bootstrap until 'task talos:secure:check' succeeds for every node."

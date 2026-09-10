#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
need_cmd yq

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"

cdrom_row() {
  local domain="$1"
  local view="$2"
  local args=(domblklist "$domain" --details)

  if [[ "$view" == "config" ]]; then
    args+=(--inactive)
  fi

  virsh -c "$LIBVIRT_URI" "${args[@]}" \
    | awk '$2 == "cdrom" && !found++ {print $3 "\t" $4}'
}

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  if ! virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    note "$name does not exist; skipping"
    continue
  fi

  config_row="$(cdrom_row "$name" config)"
  IFS=$'\t' read -r config_target config_source <<<"$config_row"

  if [[ -z "${config_target:-}" ]]; then
    note "$name: no persistent CD-ROM device exists"
  elif [[ -z "${config_source:-}" || "$config_source" == "-" ]]; then
    note "$name: persistent CD-ROM $config_target already has no media"
  else
    log "$name: ejecting $config_source from persistent CD-ROM $config_target"
    virsh -c "$LIBVIRT_URI" change-media "$name" "$config_target" --eject --config >/dev/null
  fi

  if [[ "$(virsh -c "$LIBVIRT_URI" domstate "$name")" == "running" ]]; then
    live_row="$(cdrom_row "$name" live)"
    IFS=$'\t' read -r live_target live_source <<<"$live_row"

    if [[ -z "${live_target:-}" ]]; then
      note "$name: no live CD-ROM device exists"
    elif [[ -z "${live_source:-}" || "$live_source" == "-" ]]; then
      note "$name: live CD-ROM $live_target already has no media"
    else
      log "$name: ejecting $live_source from live CD-ROM $live_target"
      virsh -c "$LIBVIRT_URI" change-media "$name" "$live_target" --eject --live >/dev/null
    fi
  fi
done < <(yq -r '.nodes[].name' "$NODES_FILE")

ok "Talos installation media is absent from all VM CD-ROMs"

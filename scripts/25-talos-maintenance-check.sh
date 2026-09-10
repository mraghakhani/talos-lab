#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
TALOS_VERSION="$(yq -r '.cluster.talos' "$PROJECT_ROOT/config/versions.yaml")"
failures=0

validate_disk() {
  local ip="$1"
  local disk_id="$2"
  local expected_gib="$3"
  local disk_out actual_id dev_path size_bytes read_only min_bytes

  if ! disk_out="$(talosctl get disk "$disk_id" --insecure --nodes "$ip" -o yaml 2>&1)"; then
    printf '%s' "$disk_id: resource lookup failed: ${disk_out//$'\n'/ }"
    return 1
  fi

  actual_id="$(yq -r '.metadata.id // ""' <<<"$disk_out")"
  dev_path="$(yq -r '.spec.dev_path // ""' <<<"$disk_out")"
  size_bytes="$(yq -r '.spec.size // 0' <<<"$disk_out")"
  read_only="$(yq -r '.spec.readonly' <<<"$disk_out")"
  min_bytes=$(( expected_gib * 1024 * 1024 * 1024 ))

  if [[ "$actual_id" != "$disk_id" ]]; then
    printf '%s' "$disk_id: unexpected resource id '$actual_id'"
    return 1
  fi
  if [[ "$dev_path" != "/dev/$disk_id" ]]; then
    printf '%s' "$disk_id: expected /dev/$disk_id, got '$dev_path'"
    return 1
  fi
  if [[ ! "$size_bytes" =~ ^[0-9]+$ ]] || (( size_bytes < min_bytes )); then
    printf '%s' "$disk_id: expected >= ${expected_gib} GiB, got ${size_bytes} bytes"
    return 1
  fi
  if [[ "$read_only" != "false" ]]; then
    printf '%s' "$disk_id: expected writable disk, readonly=$read_only"
    return 1
  fi

  return 0
}

printf '%-20s %-15s %-9s %-9s\n' NAME IP API DISKS
printf '%-20s %-15s %-9s %-9s\n' -------------------- --------------- --------- ---------

while IFS=$'\t' read -r name ip os_disk_gib data_disk_gib; do
  [[ -n "$name" ]] || continue
  api_status=FAIL
  disk_status=FAIL

  version_out="$(talosctl version --insecure --nodes "$ip" --short 2>&1 || true)"
  if grep -q "$TALOS_VERSION" <<<"$version_out"; then
    api_status=OK
  else
    ((failures+=1))
  fi

  disk_errors=()
  if ! disk_error="$(validate_disk "$ip" vda "$os_disk_gib")"; then
    disk_errors+=("$disk_error")
  fi
  if (( data_disk_gib > 0 )); then
    if ! disk_error="$(validate_disk "$ip" vdb "$data_disk_gib")"; then
      disk_errors+=("$disk_error")
    fi
  fi

  if (( ${#disk_errors[@]} == 0 )); then
    disk_status=OK
  else
    ((failures+=1))
  fi

  printf '%-20s %-15s %-9s %-9s\n' "$name" "$ip" "$api_status" "$disk_status"

  if [[ "$api_status" != OK ]]; then
    echo "  version response: ${version_out//$'\n'/ }" >&2
  fi
  if [[ "$disk_status" != OK ]]; then
    echo "  disk validation errors:" >&2
    printf '    %s\n' "${disk_errors[@]}" >&2
  fi
done < <(yq -r '.nodes[] | [.name, .ip, .os_disk_gib, .data_disk_gib] | @tsv' "$NODES_FILE")

if (( failures > 0 )); then
  die "$failures Talos maintenance-mode checks failed"
fi

ok "all nodes are reachable in Talos maintenance mode and expected disks exist"

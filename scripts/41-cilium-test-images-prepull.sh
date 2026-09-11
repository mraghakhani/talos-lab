#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd cilium-cli
need_cmd talosctl
need_cmd timeout
need_cmd yq
need_cmd awk
need_cmd sort

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"
[[ -s "$NODES_FILE" ]] || die "node inventory missing: $NODES_FILE"

PULL_RETRIES="${CILIUM_TEST_IMAGE_PULL_RETRIES:-4}"
PULL_TIMEOUT="${CILIUM_TEST_IMAGE_PULL_TIMEOUT:-180s}"

help_text="$(cilium-cli connectivity test --help 2>&1)"

mapfile -t images < <(
  awk '
    /--[[:alnum:]-]*image[[:space:]]+string/ && /\(default "/ {
      line = $0
      sub(/^.*\(default "/, "", line)
      sub(/"\).*$/, "", line)
      if (line != "") print line
    }
  ' <<<"$help_text" | sort -u
)

((${#images[@]} > 0)) || die "unable to discover connectivity-test images from cilium CLI help"

printf 'Connectivity test images (%d):\n' "${#images[@]}"
printf '  %s\n' "${images[@]}"

mapfile -t nodes < <(yq -r '.nodes[].ip' "$NODES_FILE")
((${#nodes[@]} > 0)) || die "no nodes found in $NODES_FILE"

pull_image() {
  local ip="$1"
  local image="$2"
  local attempt delay

  for ((attempt = 1; attempt <= PULL_RETRIES; attempt++)); do
    log "$ip [cri] pull $image (attempt $attempt/$PULL_RETRIES)"

    if timeout "$PULL_TIMEOUT" talosctl \
      --talosconfig "$TALOSCONFIG" \
      --endpoints "$ip" \
      --nodes "$ip" \
      image pull \
      --namespace cri \
      "$image"; then
      return 0
    fi

    if ((attempt < PULL_RETRIES)); then
      delay=$((attempt * 3))
      warn "$ip failed to pull $image; retrying in ${delay}s"
      sleep "$delay"
    fi
  done

  die "$ip failed to pull $image after $PULL_RETRIES attempts"
}

for ip in "${nodes[@]}"; do
  for image in "${images[@]}"; do
    pull_image "$ip" "$image"
  done
done

ok "Cilium connectivity-test images are pre-pulled on all Talos nodes"

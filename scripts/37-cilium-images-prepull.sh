#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd helm
need_cmd talosctl
need_cmd timeout
need_cmd yq
need_cmd awk
need_cmd sort

VERSIONS="$PROJECT_ROOT/config/versions.yaml"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
VALUES="$PROJECT_ROOT/platform/cilium/values.yaml"
GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"
[[ -s "$VALUES" ]] || die "Cilium values missing: $VALUES"

CILIUM_VERSION="$(yq -r '.platform.cilium // ""' "$VERSIONS")"
[[ -n "$CILIUM_VERSION" ]] || die "platform.cilium is not pinned in config/versions.yaml"

HOST_PROXY="${PROXY_SCHEME}://127.0.0.1:${PROXY_PORT}"
PULL_RETRIES="${CILIUM_IMAGE_PULL_RETRIES:-4}"
PULL_TIMEOUT="${CILIUM_IMAGE_PULL_TIMEOUT:-180s}"

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

log "rendering Cilium $CILIUM_VERSION chart through host proxy"
HTTP_PROXY="$HOST_PROXY" HTTPS_PROXY="$HOST_PROXY" \
  NO_PROXY="localhost,127.0.0.1,${LAB_NETWORK},${K8S_API_VIP}" \
  helm template cilium oci://quay.io/cilium/charts/cilium \
  --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --values "$VALUES" >"$rendered"

# Helm emits Kubernetes manifests where container images are scalar `image:`
# fields. Parse those fields directly instead of relying on yq-specific
# recursive-expression syntax, which differs between yq implementations.
mapfile -t images < <(
  awk '
    /^[[:space:]]*image:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*image:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      gsub(/^["'\'']|["'\'']$/, "", line)
      if (line != "") print line
    }
  ' "$rendered" | sort -u
)

((${#images[@]} > 0)) || die "no container images found in rendered Cilium chart"

printf 'Cilium images (%d):\n' "${#images[@]}"
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

ok "Cilium chart images are pre-pulled on all Talos nodes"

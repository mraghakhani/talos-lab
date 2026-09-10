#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd timeout
need_cmd yq
need_cmd grep

VERSIONS="$PROJECT_ROOT/config/versions.yaml"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"

[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"
[[ -s "$VERSIONS" ]] || die "version manifest missing: $VERSIONS"
[[ -s "$NODES_FILE" ]] || die "node inventory missing: $NODES_FILE"

KUBERNETES_VERSION="$(yq -r '.cluster.kubernetes' "$VERSIONS")"
[[ -n "$KUBERNETES_VERSION" && "$KUBERNETES_VERSION" != "null" ]] ||
  die "cluster.kubernetes is not pinned in config/versions.yaml"

PULL_RETRIES="${TALOS_IMAGE_PULL_RETRIES:-4}"
PULL_TIMEOUT="${TALOS_IMAGE_PULL_TIMEOUT:-180s}"

pull_image() {
  local ip="$1"
  local namespace="$2"
  local image="$3"
  local attempt delay

  for ((attempt = 1; attempt <= PULL_RETRIES; attempt++)); do
    log "$ip [$namespace] pull $image (attempt $attempt/$PULL_RETRIES)"

    if timeout "$PULL_TIMEOUT" talosctl \
      --talosconfig "$TALOSCONFIG" \
      --endpoints "$ip" \
      --nodes "$ip" \
      image pull \
      --namespace "$namespace" \
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

mapfile -t all_nodes < <(yq -r '.nodes[].ip' "$NODES_FILE")
mapfile -t controlplanes < <(
  yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE"
)

((${#all_nodes[@]} > 0)) || die "no nodes found in $NODES_FILE"
((${#controlplanes[@]} > 0)) || die "no control-plane nodes found in $NODES_FILE"

log "resolving Kubernetes $KUBERNETES_VERSION image bundle from talosctl"
mapfile -t bundle_images < <(
  talosctl image k8s-bundle --k8s-version "$KUBERNETES_VERSION" |
    awk 'NF {print $1}'
)

((${#bundle_images[@]} > 0)) ||
  die "talosctl image k8s-bundle returned no images"

system_images=()
cri_images=()

for image in "${bundle_images[@]}"; do
  case "$image" in
  *"/kubelet:"* | *"/etcd:"*)
    system_images+=("$image")
    ;;
  *"/flannel:"* | *"/kube-proxy:"* | *"/kube-network-policies:"*)
    note "skipping disabled/unneeded image: $image"
    ;;
  *)
    cri_images+=("$image")
    ;;
  esac
done

printf 'System images (%d):\n' "${#system_images[@]}"
printf '  %s\n' "${system_images[@]}"

printf 'CRI images (%d):\n' "${#cri_images[@]}"
printf '  %s\n' "${cri_images[@]}"

# Kubelet is needed on every node; etcd only on control planes.
for image in "${system_images[@]}"; do
  case "$image" in
  *"/etcd:"*)
    targets=("${controlplanes[@]}")
    ;;
  *)
    targets=("${all_nodes[@]}")
    ;;
  esac

  for ip in "${targets[@]}"; do
    pull_image "$ip" system "$image"
  done
done

# Pre-pull the CRI bundle on every node. This intentionally spends some disk
# space to make the lab less dependent on registry/proxy availability during
# bootstrap, rescheduling, and recovery.
for ip in "${all_nodes[@]}"; do
  for image in "${cri_images[@]}"; do
    pull_image "$ip" cri "$image"
  done
done

ok "pinned Talos/Kubernetes images are pre-pulled on all applicable nodes"

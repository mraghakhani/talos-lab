#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

VERSIONS="$PROJECT_ROOT/config/versions.yaml"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
PATCH_DIR="$PROJECT_ROOT/state/rendered/talos"
GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
SECRETS="$GENERATED/secrets.yaml"
TALOSCONFIG="$GENERATED/talosconfig"

TALOS_VERSION="$(yq -r '.cluster.talos' "$VERSIONS")"
KUBERNETES_VERSION="$(yq -r '.cluster.kubernetes' "$VERSIONS")"
KUBERNETES_VERSION="${KUBERNETES_VERSION#v}"
ENDPOINT="https://${K8S_API_VIP}:6443"

mkdir -p "$GENERATED"
chmod 700 "$GENERATED"

if [[ ! -s "$SECRETS" ]]; then
  log "generating Talos cluster secrets bundle"
  talosctl gen secrets \
    --talos-version "$TALOS_VERSION" \
    --output-file "$SECRETS"
  chmod 600 "$SECRETS"
  ok "generated ${SECRETS#"$PROJECT_ROOT"/}"
else
  log "reusing existing Talos secrets bundle (cluster identity remains stable)"
fi

for f in "$PATCH_DIR/common.yaml" "$PATCH_DIR/controlplane.yaml" "$PATCH_DIR/worker.yaml"; do
  [[ -s "$f" ]] || die "rendered patch missing: $f; run task talos:render"
done

while IFS=$'\t' read -r name role; do
  [[ -n "$name" ]] || continue
  node_patch="$PATCH_DIR/nodes/${name}.yaml"
  outfile="$GENERATED/${name}.yaml"
  [[ -s "$node_patch" ]] || die "node patch missing: $node_patch"

  case "$role" in
    controlplane) output_type=controlplane ;;
    worker) output_type=worker ;;
    *) die "unsupported node role '$role' for $name" ;;
  esac

  log "generating $name ($output_type)"
  talosctl gen config \
    "$CLUSTER_NAME" "$ENDPOINT" \
    --with-secrets "$SECRETS" \
    --talos-version "$TALOS_VERSION" \
    --kubernetes-version "$KUBERNETES_VERSION" \
    --install-disk "$TALOS_INSTALL_DISK" \
    --with-docs=false \
    --with-examples=false \
    --config-patch "@$PATCH_DIR/common.yaml" \
    --config-patch "@$PATCH_DIR/${role}.yaml" \
    --config-patch "@$node_patch" \
    --output-types "$output_type" \
    --output "$outfile" \
    --force
  chmod 600 "$outfile"
done < <(yq -r '.nodes[] | [.name, .role] | @tsv' "$NODES_FILE")

log "generating Talos client configuration"
talosctl gen config \
  "$CLUSTER_NAME" "$ENDPOINT" \
  --with-secrets "$SECRETS" \
  --talos-version "$TALOS_VERSION" \
  --kubernetes-version "$KUBERNETES_VERSION" \
  --output-types talosconfig \
  --output "$TALOSCONFIG" \
  --force
chmod 600 "$TALOSCONFIG"

mapfile -t controlplane_ips < <(yq -r '.nodes[] | select(.role == "controlplane") | .ip' "$NODES_FILE")
(( ${#controlplane_ips[@]} > 0 )) || die "no control-plane nodes found"

talosctl --talosconfig "$TALOSCONFIG" config endpoint "${controlplane_ips[@]}"
talosctl --talosconfig "$TALOSCONFIG" config node "${controlplane_ips[0]}"

ok "generated six node-specific configs plus talosconfig using pinned versions"
echo "Generated directory: $GENERATED"
echo "Kubernetes endpoint: $ENDPOINT"
echo "Talos endpoints: ${controlplane_ips[*]}"

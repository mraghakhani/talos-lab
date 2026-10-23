#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Capture containerd image stores from live Talos nodes over the Talos API, so
# the rebuilt cluster never re-downloads existing images through the host
# proxy. Fully Talos-native: no SSH, no disk mounts, no service stops, and no
# registry pulls — images already present on the nodes are captured as-is.
#
# Phases:
#   1. Inventory: record image lists (namespaces cri + system) from every node.
#   2. Capture: for each node that adds images not already covered by the
#      captured set (greedy cover), stream /var/lib/containerd as .tar.gz via
#      talosctl copy. Consistency is verified deterministically: the containerd
#      bolt metadata DB checksum must be identical before and after each copy
#      attempt (content store blobs are immutable, so the metadata DB is the
#      only mutable piece that matters).
#
# Restore (task images:restore) seeds fresh nodes with one primary store and
# merges the content blobs of the remaining captures into it, so every node
# gets the full image set offline. Same Talos version required: the containerd
# metadata database is version-coupled.

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
TALOSCONFIG="$GENERATED/talosconfig"
BACKUP_DIR="${IMAGE_BACKUP_DIR:-$PROJECT_ROOT/state/image-backup}"
INVENTORY_DIR="$BACKUP_DIR/inventory"
CAPTURE_ATTEMPTS="${IMAGE_BACKUP_ATTEMPTS:-3}"
BOLT_DB="/var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db"
STORE_DIR="/var/lib/containerd"

[[ -s "$NODES_FILE" ]] || die "node inventory missing: $NODES_FILE"
[[ -s "$TALOSCONFIG" ]] || die "talosconfig missing; run task talos:generate"

need_cmd talosctl
need_cmd yq
need_cmd sha256sum
need_cmd comm

node_ip() {
  yq -r ".nodes[] | select(.name == \"$1\") | .ip" "$NODES_FILE"
}

tctl() {
  local ip="$1"
  shift
  talosctl --talosconfig "$TALOSCONFIG" --endpoints "$ip" --nodes "$ip" "$@"
}

# Second column of talosctl image list output is the image reference
# (columns: NODE IMAGE DIGEST SIZE LABELS CREATED).
inv_refs() {
  awk 'NF > 1 && $2 !~ /^IMAGE$/ { print $2 }' "$@" | sort -u
}

bolt_sha() {
  local ip="$1"
  tctl "$ip" read "$BOLT_DB" | sha256sum | awk '{print $1}'
}

inventory_phase() {
  local name ip ns
  mkdir -p "$INVENTORY_DIR"
  while IFS=$'\t' read -r name _role ip _mac; do
    [[ -n "$name" ]] || continue
    for ns in cri system; do
      log "inventory $name ($ip) namespace=$ns"
      if ! tctl "$ip" image list --namespace "$ns" > "$INVENTORY_DIR/${name}.${ns}.txt"; then
        warn "$name namespace=$ns inventory failed; continuing"
      fi
    done
  done < <(yq -r '.nodes[] | [.name, .role, .ip, .mac] | @tsv' "$NODES_FILE")
  ok "image inventories written under inventory/"
}

capture_node() {
  local name="$1" ip attempt pre_sha post_sha out tmp size_mb
  ip="$(node_ip "$name")"
  [[ -n "$ip" ]] || die "no IP found for $name in $NODES_FILE"

  out="$BACKUP_DIR/containerd-$name.tar.gz"
  tmp="$out.tmp"

  for (( attempt = 1; attempt <= CAPTURE_ATTEMPTS; attempt++ )); do
    log "$name capture attempt $attempt/$CAPTURE_ATTEMPTS"
    pre_sha="$(bolt_sha "$ip")"
    if ! tctl "$ip" copy "$STORE_DIR" - > "$tmp"; then
      warn "copy failed on attempt $attempt"
      continue
    fi
    post_sha="$(bolt_sha "$ip")"
    if [[ "$pre_sha" == "$post_sha" ]]; then
      mv "$tmp" "$out"
      sha256sum "$out" > "$out.sha256"
      size_mb="$(du -m "$out" | awk '{print $1}')"
      ok "$name captured -> ${out#"$PROJECT_ROOT"/} (${size_mb}MiB)"
      return 0
    fi
    warn "$name containerd metadata changed during copy; retrying"
    rm -f "$tmp"
  done
  rm -f "$tmp"
  die "$name capture failed after $CAPTURE_ATTEMPTS attempts (metadata kept changing)"
}

# Greedy cover: capture nodes ordered by distinct image count (descending),
# skipping any node whose images are all covered by captures so far.
capture_phase() {
  local name count covered="$BACKUP_DIR/covered.refs"
  : > "$covered"

  while read -r count name; do
    [[ -n "$name" ]] || continue
    if [[ ! -s "$INVENTORY_DIR/$name.cri.txt" && ! -s "$INVENTORY_DIR/$name.system.txt" ]]; then
      warn "$name has no inventory; skipping capture"
      continue
    fi
    inv_refs "$INVENTORY_DIR/$name".cri.txt "$INVENTORY_DIR/$name".system.txt \
      > "$BACKUP_DIR/$name.refs"
    if [[ -z "$(comm -23 "$BACKUP_DIR/$name.refs" "$covered")" ]]; then
      note "$name adds no new images; skipping capture"
      continue
    fi
    capture_node "$name"
    sort -u "$covered" "$BACKUP_DIR/$name.refs" > "$covered.tmp"
    mv "$covered.tmp" "$covered"
  done < <(
    while IFS=$'\t' read -r name _rest; do
      [[ -n "$name" ]] || continue
      if [[ -s "$INVENTORY_DIR/$name.cri.txt" || -s "$INVENTORY_DIR/$name.system.txt" ]]; then
        count="$(inv_refs "$INVENTORY_DIR/$name".cri.txt "$INVENTORY_DIR/$name".system.txt | wc -l)"
      else
        count=0
      fi
      printf '%s %s\n' "$count" "$name"
    done < <(yq -r '.nodes[] | .name' "$NODES_FILE") | sort -rn
  )
}

mkdir -p "$BACKUP_DIR"
inventory_phase
capture_phase

note "restore with task images:restore on freshly installed nodes before bootstrap"
note "same Talos version required (currently v${TALOS_VERSION})"
ok "image store backup complete"

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd envsubst

TEMPLATE="$PROJECT_ROOT/infrastructure/libvirt/pool.xml.tmpl"
OUT_DIR="$PROJECT_ROOT/state/rendered"
OUT="$OUT_DIR/pool.xml"
mkdir -p "$OUT_DIR"

export LIBVIRT_POOL LIBVIRT_POOL_PATH
envsubst < "$TEMPLATE" > "$OUT"
log "Rendered $OUT"

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd curl
need_cmd sha256sum
need_cmd virsh

SUMS_CACHE="$CACHE_DIR/sha256sum.txt"
BASE="${TALOS_RELEASE_BASE_URL}/${TALOS_VERSION}"
HOST_PROXY="${PROXY_SCHEME}://127.0.0.1:${PROXY_PORT}"
POOL_ISO="${LIBVIRT_POOL_PATH}/${TALOS_ISO_NAME}"

mkdir -p "$CACHE_DIR"

log "Downloading Talos $TALOS_VERSION checksums through host proxy"
curl --fail --location --retry 3 --proxy "$HOST_PROXY" \
  "$BASE/sha256sum.txt" -o "$SUMS_CACHE"

if [[ ! -f "$ISO_CACHE" ]]; then
  log "Downloading $TALOS_ISO_NAME"
  curl --fail --location --retry 3 --continue-at - --proxy "$HOST_PROXY" \
    "$BASE/$TALOS_ISO_NAME" -o "$ISO_CACHE"
else
  log "Using cached $ISO_CACHE"
fi

log "Verifying SHA-256"
(
  cd "$CACHE_DIR"
  grep "  ${TALOS_ISO_NAME}$" sha256sum.txt | sha256sum --check --strict -
)

# Copy into the system libvirt pool through the libvirt daemon (same access
# level as every other virsh operation in this repo; no root shell required).
# The pool volume is a derived copy of the verified cache, so replace it
# wholesale on every run.
log "Copying verified ISO into libvirt pool"
if virsh -c "$LIBVIRT_URI" vol-info "$TALOS_ISO_NAME" --pool "$LIBVIRT_POOL" >/dev/null 2>&1; then
  virsh -c "$LIBVIRT_URI" vol-delete "$TALOS_ISO_NAME" --pool "$LIBVIRT_POOL" >/dev/null
fi
virsh -c "$LIBVIRT_URI" vol-create-as "$LIBVIRT_POOL" "$TALOS_ISO_NAME" \
  "$(stat -c %s "$ISO_CACHE")" --format raw >/dev/null
virsh -c "$LIBVIRT_URI" vol-upload --pool "$LIBVIRT_POOL" "$TALOS_ISO_NAME" "$ISO_CACHE" >/dev/null
virsh -c "$LIBVIRT_URI" pool-refresh "$LIBVIRT_POOL" >/dev/null

echo "OK   $POOL_ISO"

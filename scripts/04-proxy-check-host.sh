#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need_cmd curl
need_cmd ss

LOCAL_PROXY="${PROXY_SCHEME}://127.0.0.1:${PROXY_PORT}"
VM_PROXY="${PROXY_SCHEME}://${PROXY_HOST}:${PROXY_PORT}"

log "Checking listener on TCP $PROXY_PORT"
ss -ltnp 2>/dev/null | awk -v p=":${PROXY_PORT}" '$4 ~ p {print}' || true

log "Checking HTTPS CONNECT through host-local proxy: $LOCAL_PROXY"
# Any HTTP status proves the TCP+CONNECT path reached the registry.
curl --silent --show-error --head --max-time 10 \
  --proxy "$LOCAL_PROXY" \
  https://registry.k8s.io/v2/ >/dev/null

echo "OK   registry.k8s.io reachable through $LOCAL_PROXY"

log "VM-facing proxy address will be: $VM_PROXY"
echo "NOTE The next milestone verifies this from the libvirt subnet itself."

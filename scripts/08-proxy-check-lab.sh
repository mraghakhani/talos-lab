#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd curl
need_cmd ss

VM_PROXY="${PROXY_SCHEME}://${PROXY_HOST}:${PROXY_PORT}"

ip link show "$LAB_BRIDGE" >/dev/null 2>&1 || die "$LAB_BRIDGE does not exist; run task network:up first"

log "Checking proxy is listening on a VM-reachable address"
listeners="$(ss -H -ltn 2>/dev/null | awk -v p=":${PROXY_PORT}" '$4 ~ p {print $4}')"
[[ -n "$listeners" ]] || die "nothing is listening on TCP ${PROXY_PORT}"
echo "$listeners"

if ! grep -Eq "(^|\[)${PROXY_HOST//./\\.}:${PROXY_PORT}$|0\.0\.0\.0:${PROXY_PORT}$|\*:${PROXY_PORT}$|\[::\]:${PROXY_PORT}$" <<<"$listeners"; then
  die "proxy is not reachable at ${PROXY_HOST}:${PROXY_PORT}; it may be bound only to loopback"
fi

log "Checking registry access through VM-facing proxy: $VM_PROXY"
curl --silent --show-error --head --max-time 15 \
  --proxy "$VM_PROXY" \
  https://registry.k8s.io/v2/ >/dev/null

echo "OK   registry.k8s.io reachable through $VM_PROXY"
echo "OK   Talos nodes can use this address once booted"

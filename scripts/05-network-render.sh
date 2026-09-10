#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd envsubst
need_cmd yq

TEMPLATE="$PROJECT_ROOT/infrastructure/libvirt/network.xml.tmpl"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
OUT_DIR="$PROJECT_ROOT/state/rendered"
OUT="$OUT_DIR/network.xml"

mkdir -p "$OUT_DIR"

DHCP_HOSTS_XML=""
while IFS=$'\t' read -r name ip mac; do
  DHCP_HOSTS_XML+="      <host mac='${mac}' name='${name}' ip='${ip}'/>"$'\n'
done < <(yq -r '.nodes[] | [.name, .ip, .mac] | @tsv' "$NODES_FILE")
DHCP_HOSTS_XML="${DHCP_HOSTS_XML%$'\n'}"

export LAB_NAME LAB_BRIDGE LAB_GATEWAY LAB_NETMASK
export DHCP_DYNAMIC_START DHCP_DYNAMIC_END DHCP_HOSTS_XML

envsubst < "$TEMPLATE" > "$OUT"

log "Rendered $OUT from config/lab.env + config/nodes.yaml"

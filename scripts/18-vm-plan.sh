#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need_cmd yq
need_cmd virsh

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
ISO_PATH="$LIBVIRT_POOL_PATH/$TALOS_ISO_NAME"

printf '%-20s %-13s %-16s %-18s %5s %8s %8s %9s\n' \
  NAME ROLE IP MAC VCPU RAM_MIB OS_GIB DATA_GIB
printf '%-20s %-13s %-16s %-18s %5s %8s %8s %9s\n' \
  '--------------------' '-------------' '----------------' '------------------' '-----' '--------' '--------' '---------'

nodes=0
total_vcpu=0
total_mem=0
total_disk=0
while IFS=$'\t' read -r name role ip mac vcpus memory os_disk data_disk; do
  [[ -n "$name" ]] || continue
  printf '%-20s %-13s %-16s %-18s %5s %8s %8s %9s\n' \
    "$name" "$role" "$ip" "$mac" "$vcpus" "$memory" "$os_disk" "$data_disk"
  ((nodes+=1))
  ((total_vcpu+=vcpus))
  ((total_mem+=memory))
  ((total_disk+=os_disk+data_disk))
done < <(yq -r '.nodes[] | [.name, .role, .ip, .mac, .vcpus, .memory_mib, .os_disk_gib, .data_disk_gib] | @tsv' "$NODES_FILE")

echo
printf 'Nodes:              %d\n' "$nodes"
printf 'Total vCPU:         %d\n' "$total_vcpu"
printf 'Total RAM:          %.1f GiB\n' "$(awk -v m="$total_mem" 'BEGIN {printf "%.1f", m/1024}')"
printf 'Virtual disk cap:   %d GiB (qcow2 thin-provisioned)\n' "$total_disk"
printf 'API VIP:            %s\n' "$K8S_API_VIP"
printf 'VM proxy:           %s://%s:%s\n' "$PROXY_SCHEME" "$PROXY_HOST" "$PROXY_PORT"
printf 'Talos ISO:          %s\n' "$ISO_PATH"

echo
virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME" >/dev/null 2>&1 \
  && echo "OK   network '$LAB_NAME' is defined" \
  || { echo "MISS network '$LAB_NAME'"; exit 1; }
virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL" >/dev/null 2>&1 \
  && echo "OK   storage pool '$LIBVIRT_POOL' is defined" \
  || { echo "MISS storage pool '$LIBVIRT_POOL'"; exit 1; }
[[ -f "$ISO_PATH" ]] \
  && echo "OK   verified Talos ISO is staged in the libvirt pool" \
  || { echo "MISS Talos ISO; run: task image:download"; exit 1; }

existing=0
while read -r name; do
  [[ -n "$name" ]] || continue
  if virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    echo "NOTE VM already exists: $name"
    ((existing+=1))
  fi
done < <(yq -r '.nodes[].name' "$NODES_FILE")

if (( existing == 0 )); then
  echo "OK   none of the desired VM domains exist yet"
else
  echo "NOTE $existing desired VM domain(s) already exist; vm:create is idempotent"
fi

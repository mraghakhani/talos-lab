#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd virsh
need_cmd virt-install
need_cmd yq

NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
ISO_PATH="$LIBVIRT_POOL_PATH/$TALOS_ISO_NAME"

[[ -f "$ISO_PATH" ]] || die "Talos ISO missing at $ISO_PATH; run task image:download"
virsh -c "$LIBVIRT_URI" net-info "$LAB_NAME" >/dev/null 2>&1 || die "network '$LAB_NAME' is not defined"
virsh -c "$LIBVIRT_URI" pool-info "$LIBVIRT_POOL" >/dev/null 2>&1 || die "pool '$LIBVIRT_POOL' is not defined"

create_volume() {
  local volume="$1" size_gib="$2"
  if virsh -c "$LIBVIRT_URI" vol-info --pool "$LIBVIRT_POOL" "$volume" >/dev/null 2>&1; then
    log "volume already exists: $volume"
  else
    log "creating volume: $volume (${size_gib} GiB)"
    virsh -c "$LIBVIRT_URI" vol-create-as \
      --pool "$LIBVIRT_POOL" \
      --name "$volume" \
      --capacity "${size_gib}G" \
      --format qcow2 >/dev/null
  fi
}

while IFS=$'\t' read -r name role ip mac vcpus memory os_disk data_disk; do
  [[ -n "$name" ]] || continue

  if virsh -c "$LIBVIRT_URI" dominfo "$name" >/dev/null 2>&1; then
    log "domain already exists: $name"
    continue
  fi

  os_volume="${name}-os.qcow2"
  create_volume "$os_volume" "$os_disk"

  disk_args=(--disk "vol=${LIBVIRT_POOL}/${os_volume},bus=virtio,cache=none,discard=unmap")

  if (( data_disk > 0 )); then
    data_volume="${name}-data.qcow2"
    create_volume "$data_volume" "$data_disk"
    disk_args+=(--disk "vol=${LIBVIRT_POOL}/${data_volume},bus=virtio,cache=none,discard=unmap")
  fi

  log "defining and starting $name ($role, $ip)"
  virt-install \
    --connect "$LIBVIRT_URI" \
    --virt-type kvm \
    --name "$name" \
    --memory "$memory" \
    --vcpus "$vcpus" \
    --cpu host-passthrough \
    "${disk_args[@]}" \
    --cdrom "$ISO_PATH" \
    --os-variant linux2022 \
    --network "network=${LAB_NAME},model=virtio,mac=${mac}" \
    --graphics none \
    --console pty,target.type=serial \
    --rng /dev/urandom \
    --boot hd,cdrom \
    --noautoconsole

done < <(yq -r '.nodes[] | [.name, .role, .ip, .mac, .vcpus, .memory_mib, .os_disk_gib, .data_disk_gib] | @tsv' "$NODES_FILE")

virsh -c "$LIBVIRT_URI" list --all

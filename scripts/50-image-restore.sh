#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Seed the containerd image store of freshly installed Talos nodes from the
# capture archives created by scripts/49-image-backup.sh, so the rebuilt
# cluster never re-downloads existing images through the host proxy.
#
# Why disk-level: talosctl copy is out-only (no write-in API on Talos), so the
# store archives are injected by mounting the node's VM disk here on the host.
#
# How the multiple captures combine:
#   - The primary archive (richest store, default talos-cp-01) seeds the node
#     wholesale: metadata DB (image refs) + content blobs + snapshots.
#   - Each other archive contributes only its content blobs (digest-addressed
#     and immutable, so merging is copy-if-missing). Their image refs are NOT
#     registered offline; at first pod-schedule the manifest/config alone is
#     fetched from the registry (a few KB) while every layer blob resolves
#     locally — no bulk re-download.
#
# Sequencing and requirements:
#   - Run AFTER the node disk has Talos installed (first boot completed) and
#     with the VM shut off. Typical point: after talos:apply, before
#     talos:bootstrap.
#   - Same Talos version as the capture: the containerd metadata database
#     (bolt) is version-coupled.
#   - The primary store replaces the node's containerd directory wholesale;
#     the previous content is kept as containerd.pre-seed for manual rollback.
#
# The target partition is found by GPT label STATE first, then by signature
# scan (the store root contains io.containerd.metadata.v1.bolt), never by
# size guessing.
#
# Env overrides:
#   IMAGE_RESTORE_TARS   comma-separated capture archives, primary first
#                        (default: every containerd-*.tar.gz, cp-01 first)
#   IMAGE_RESTORE_NBD    nbd device (default: /dev/nbd0)
#   IMAGE_RESTORE_NODES  comma-separated node names (default: all in nodes.yaml)

BACKUP_DIR="${IMAGE_BACKUP_DIR:-$PROJECT_ROOT/state/image-backup}"
NBD_DEVICE="${IMAGE_RESTORE_NBD:-/dev/nbd0}"
MOUNT_DIR="/mnt/talos-image-restore"
SEED_MARKER=".image-backup-seed"
CONTENT_DIR="io.containerd.content.v1.content"

[[ -s "$NODES_FILE" ]] || die "node inventory missing: $NODES_FILE"

need_cmd virsh
need_cmd qemu-nbd
need_cmd tar
need_cmd yq
need_cmd sha256sum
need_cmd lsblk
need_cmd partprobe
need_cmd partx

default_tars() {
  local t list=""
  for t in "$BACKUP_DIR/containerd-talos-cp-01.tar.gz" "$BACKUP_DIR"/containerd-*.tar.gz; do
    [[ -s "$t" ]] || continue
    case ",$list," in
      *",$t,"*) continue ;;
    esac
    list="${list:+$list,}$t"
  done
  printf '%s' "$list"
}

# shellcheck disable=SC2206  # intentional comma-separated list splitting
IFS=',' read -r -a restore_tars <<< "${IMAGE_RESTORE_TARS:-$(default_tars)}"
[[ ${#restore_tars[@]} -gt 0 && -n "${restore_tars[0]}" ]] || die "no capture archives found under ${BACKUP_DIR#"$PROJECT_ROOT"/}"

# shellcheck disable=SC2206  # intentional comma-separated list splitting
IFS=',' read -r -a restore_nodes <<< "${IMAGE_RESTORE_NODES:-$(yq -r '.nodes[].name' "$NODES_FILE" | paste -sd,)}"

((${#restore_nodes[@]} > 0)) || die "no nodes selected for restore"

for t in "${restore_tars[@]}"; do
  [[ -s "$t" ]] || die "capture archive missing: $t"
  [[ -s "$t.sha256" ]] || die "sha256 file missing for $t"
  log "verifying ${t#"$PROJECT_ROOT"/}"
  (cd "$(dirname "$t")" && sha256sum -c "$(basename "$t").sha256") \
    || die "sha256 mismatch for $t"
done
PRIMARY_TAR="${restore_tars[0]}"

vm_state() {
  local name="$1" state
  state="$(virsh -c "$LIBVIRT_URI" domstate "$name" 2>/dev/null | tr -d '\r')" || state="absent"
  printf '%s' "$state"
}

MOUNTED=""
NBD_CONNECTED=""
cleanup_restore() {
  if [[ -n "$MOUNTED" ]]; then
    sudo umount "$MOUNT_DIR" || true
  fi
  if [[ -n "$NBD_CONNECTED" ]]; then
    sudo qemu-nbd --disconnect "$NBD_DEVICE" || true
  fi
  MOUNTED=""
  NBD_CONNECTED=""
}
trap cleanup_restore EXIT

# Mount the partition that holds the containerd store: prefer the partition
# labeled STATE (Talos mounts it at /var), fall back to a signature scan for
# the store's bolt metadata directory so this works regardless of layout.
mount_store_partition() {
  local part parts found=""
  mapfile -t parts < <(lsblk -rno NAME "$NBD_DEVICE" | tail -n +2)
  ((${#parts[@]} > 0)) || die "no partitions found on $NBD_DEVICE"

  sudo mkdir -p "$MOUNT_DIR"

  # First pass: the partition whose GPT label is STATE.
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    if [[ "$(lsblk -rno PARTLABEL "/dev/$part" 2>/dev/null)" == "STATE" ]]; then
      if sudo mount -o rw "/dev/$part" "$MOUNT_DIR" 2>/dev/null; then
        MOUNTED=1
        log "store partition: /dev/$part (label STATE)"
        return 0
      fi
    fi
  done

  # Second pass: first partition containing the containerd store, or the /var
  # layout (lib/ and log/ siblings) on a fresh node.
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
    if ! sudo mount -o rw "/dev/$part" "$MOUNT_DIR" 2>/dev/null; then
      continue
    fi
    if [[ -d "$MOUNT_DIR/lib/containerd/io.containerd.metadata.v1.bolt" ]] \
       || [[ -d "$MOUNT_DIR/var/lib/containerd/io.containerd.metadata.v1.bolt" ]] \
       || { [[ -d "$MOUNT_DIR/lib" ]] && [[ -d "$MOUNT_DIR/log" ]]; }; then
      found="$part"
      MOUNTED=1
      break
    fi
    sudo umount "$MOUNT_DIR" 2>/dev/null || true
  done
  [[ -n "$found" ]] || die "no partition with the containerd store found; partitions tried: ${parts[*]}"
  log "store partition: /dev/$found"
}

# Merge content blobs from a secondary archive into the seeded store.
merge_content_blobs() {
  local tarfile="$1" store_dir="$2" tmp_extract store_root src_blobs dst_blobs count

  tmp_extract="$MOUNT_DIR/.image-seed-merge"
  sudo rm -rf "$tmp_extract"
  sudo mkdir -p "$tmp_extract"
  log "merging content blobs from ${tarfile#"$PROJECT_ROOT"/}"
  sudo tar -C "$tmp_extract" -xf "$tarfile"

  store_root="$(sudo find "$tmp_extract" -maxdepth 4 -type d \
    -name "$CONTENT_DIR" -print -quit | sed "s|/$CONTENT_DIR\$||")"
  [[ -n "$store_root" ]] || die "content store not found inside $tarfile"

  src_blobs="$store_root/$CONTENT_DIR/blobs"
  dst_blobs="$store_dir/$CONTENT_DIR/blobs"
  sudo mkdir -p "$dst_blobs"
  # copy-if-missing: blobs are digest-addressed and immutable.
  count="$(sudo find "$src_blobs" -type f | wc -l)"
  sudo cp -rn "$src_blobs/." "$dst_blobs/"
  sudo rm -rf "$tmp_extract"
  ok "merged $count blobs from ${tarfile#"$PROJECT_ROOT"/}"
}

restore_node() {
  local name="$1" state src store_parent tmp_extract store_root size_mb t

  state="$(vm_state "$name")"
  if [[ "$state" != "shut off" ]]; then
    die "VM $name is '$state'; it must be shut off to seed its image store"
  fi

  src="$(virsh -c "$LIBVIRT_URI" domblklist "$name" --details \
    | awk '$1 == "file" && $2 == "disk" && !seen { src = $4; seen = 1 } END { print src }')"
  [[ -n "$src" ]] || die "no disk source found for VM $name"

  sudo modprobe nbd max_part=16 2>/dev/null || true
  # modprobe no-ops when the module is already loaded, possibly without the
  # max_part parameter; with max_part=0 the kernel never scans a partition
  # table on nbd devices and every later mount step would find nothing.
  if [[ "$(cat /sys/module/nbd/parameters/max_part 2>/dev/null)" == "0" ]]; then
    sudo rmmod nbd 2>/dev/null || true
    sudo modprobe nbd max_part=16
  fi
  [[ -e "$NBD_DEVICE" ]] || die "$NBD_DEVICE missing; the nbd kernel module is not available"
  if [[ "$(lsblk -rno NAME "$NBD_DEVICE" | tail -n +2)" != "" ]]; then
    die "$NBD_DEVICE already has partitions attached; free it or set IMAGE_RESTORE_NBD"
  fi

  NBD_CONNECTED=1
  connect_err=""
  if ! connect_err="$(sudo qemu-nbd --connect="$NBD_DEVICE" "$src" 2>&1)"; then
    die "qemu-nbd failed to connect $src to $NBD_DEVICE: $connect_err"
  fi

  # Partition table scan is asynchronous; poll instead of a fixed sleep.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sudo partprobe "$NBD_DEVICE" 2>/dev/null || true
    # partx creates the partition nodes explicitly via BLKPG when the
    # automatic rescan does not (observed on kernel 7.x nbd devices).
    sudo partx -a "$NBD_DEVICE" 2>/dev/null || true
    if [[ "$(lsblk -rno NAME "$NBD_DEVICE" | tail -n +2)" != "" ]]; then
      break
    fi
    if (( i < 10 )); then
      sleep 1
    fi
  done
  if [[ "$(lsblk -rno NAME "$NBD_DEVICE" | tail -n +2)" == "" ]]; then
    sudo lsblk -o NAME,SIZE,TYPE,PARTLABEL "$NBD_DEVICE" >&2 || true
    sudo sfdisk -l "$NBD_DEVICE" >&2 || true
    warn "nbd partscan=$(cat "/sys/block/${NBD_DEVICE#/dev/}/partscan" 2>/dev/null || echo unknown)"
    die "no partitions appeared on $NBD_DEVICE after connecting $src"
  fi

  mount_store_partition

  if [[ -d "$MOUNT_DIR/lib/containerd" ]]; then
    store_parent="$MOUNT_DIR/lib"
  elif [[ -d "$MOUNT_DIR/var/lib/containerd" ]]; then
    store_parent="$MOUNT_DIR/var/lib"
  else
    store_parent="$MOUNT_DIR/lib"
  fi

  if [[ -e "$store_parent/containerd/$SEED_MARKER" ]]; then
    ok "$name already seeded; skipping"
    cleanup_restore
    return 0
  fi

  # Extract on the mount itself (same filesystem) then move into place, so the
  # archive layout never has to match the target layout exactly.
  tmp_extract="$MOUNT_DIR/.image-seed-extract"
  sudo rm -rf "$tmp_extract"
  sudo mkdir -p "$tmp_extract"

  log "$name extracting primary store ${PRIMARY_TAR#"$PROJECT_ROOT"/}"
  sudo tar -C "$tmp_extract" -xf "$PRIMARY_TAR"

  store_root="$(sudo find "$tmp_extract" -maxdepth 4 -type d \
    -name 'io.containerd.metadata.v1.bolt' -print -quit | sed 's|/io\.containerd\.metadata\.v1\.bolt$||')"
  [[ -n "$store_root" ]] || die "bolt metadata directory not found inside $PRIMARY_TAR"
  log "$name store root in archive: ${store_root#"$tmp_extract"/}"

  if [[ -d "$store_parent/containerd" ]]; then
    sudo mv "$store_parent/containerd" "$store_parent/containerd.pre-seed"
  fi
  sudo mkdir -p "$store_parent"
  sudo mv "$store_root" "$store_parent/containerd"
  sudo rm -rf "$tmp_extract"
  sudo touch "$store_parent/containerd/$SEED_MARKER"

  for t in "${restore_tars[@]:1}"; do
    merge_content_blobs "$t" "$store_parent/containerd"
  done

  size_mb="$(sudo du -sm "$store_parent/containerd" | awk '{print $1}')"
  cleanup_restore
  ok "$name image store seeded (${size_mb}MiB)"
}

for name in "${restore_nodes[@]}"; do
  restore_node "$name"
done

note "images missing from the primary store resolve manifests on first schedule"
note "(a few KB through the proxy; layer blobs come from the merged captures)"
note "rollback: shut off the VM, then swap lib/containerd.pre-seed back into place"
note "nodes must run the same Talos version as the captured store (v${TALOS_VERSION})"
ok "image store restore complete"

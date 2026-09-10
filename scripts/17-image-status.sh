#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

need_cmd sha256sum

CACHE_DIR="$PROJECT_ROOT/state/downloads/talos/$TALOS_VERSION"
ISO_CACHE="$CACHE_DIR/$TALOS_ISO_NAME"
SUMS_CACHE="$CACHE_DIR/sha256sum.txt"
POOL_ISO="$LIBVIRT_POOL_PATH/$TALOS_ISO_NAME"

printf '%-18s %s\n' 'Talos version:' "$TALOS_VERSION"
printf '%-18s %s\n' 'Cached ISO:' "$ISO_CACHE"
printf '%-18s %s\n' 'Pool ISO:' "$POOL_ISO"

echo
if [[ -f "$ISO_CACHE" ]]; then
  echo "OK   cached ISO exists ($(du -h "$ISO_CACHE" | awk '{print $1}'))"
else
  echo "MISS cached ISO"
fi

if [[ -f "$SUMS_CACHE" ]]; then
  echo "OK   checksum manifest exists"
  if [[ -f "$ISO_CACHE" ]]; then
    expected_line="$(grep -E "(^|[[:space:]])(\\./)?${TALOS_ISO_NAME}$" "$SUMS_CACHE" | head -n1 || true)"
    if [[ -z "$expected_line" ]]; then
      echo "WARN checksum entry for $TALOS_ISO_NAME not found"
    else
      expected_hash="$(awk '{print $1}' <<<"$expected_line")"
      actual_hash="$(sha256sum "$ISO_CACHE" | awk '{print $1}')"
      if [[ "$expected_hash" == "$actual_hash" ]]; then
        echo "OK   cached ISO checksum matches"
      else
        echo "ERROR cached ISO checksum mismatch" >&2
        exit 1
      fi
    fi
  fi
else
  echo "MISS checksum manifest"
fi

if [[ -f "$POOL_ISO" ]]; then
  echo "OK   libvirt pool ISO exists ($(du -h "$POOL_ISO" | awk '{print $1}'))"
else
  echo "MISS libvirt pool ISO"
fi

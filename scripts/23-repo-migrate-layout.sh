#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

migrated=0

# Archive overlays do not remove files that were deleted/renamed in newer
# revisions. Keep an explicit list so migrations stay deterministic.
legacy_scripts=(
  scripts/05-network-up.sh
  scripts/06-network-status.sh
  scripts/07-network-destroy.sh
)

for path in "${legacy_scripts[@]}"; do
  if [[ -e "$path" ]]; then
    rm -- "$path"
    echo "OK   removed obsolete $path"
    migrated=1
  fi
done

if [[ -d libvirt ]]; then
  for name in network.xml.tmpl pool.xml.tmpl; do
    old="libvirt/$name"
    new="infrastructure/libvirt/$name"
    if [[ -e "$old" ]]; then
      [[ -e "$new" ]] || {
        echo "ERROR: $old exists but $new does not; refusing migration" >&2
        exit 1
      }
      cmp -s "$old" "$new" || {
        echo "ERROR: $old differs from $new; review changes before removing legacy directory" >&2
        exit 1
      }
    fi
  done

  rm -rf libvirt
  echo "OK   removed legacy libvirt/ after verifying templates match infrastructure/libvirt/"
  migrated=1
fi

if (( migrated == 0 )); then
  echo "OK   repository layout is already current"
fi

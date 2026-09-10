#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOOLS_FILE="$PROJECT_ROOT/config/tools.yaml"

command -v yq >/dev/null 2>&1 || {
  echo "ERROR: yq is required. Run: task host:install" >&2
  exit 1
}

mapfile -t packages < <(yq -r '.packages[]' "$TOOLS_FILE")
((${#packages[@]} > 0)) || {
  echo "ERROR: no packages defined in $TOOLS_FILE" >&2
  exit 1
}

sudo pacman -S --needed "${packages[@]}"

echo
echo "Developer/platform CLI packages installed."
echo "NOTE: talosctl remains separately versioned to match config/versions.yaml."

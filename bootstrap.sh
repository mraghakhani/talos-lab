#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for a fresh CachyOS/Arch host.
# After this succeeds, use `task ...` for all lab operations.
if ! command -v task >/dev/null 2>&1; then
  echo '==> Installing go-task'
  sudo pacman -S --needed go-task
fi

exec task bootstrap

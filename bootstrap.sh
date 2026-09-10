#!/usr/bin/env bash
set -euo pipefail

# One-time bootstrap for a fresh CachyOS/Arch host.
# Arch's go-task package installs /usr/bin/go-task; some users expose `task`
# through an alias or wrapper. Non-interactive scripts cannot rely on aliases.
resolve_task() {
  command -v task 2>/dev/null || command -v go-task 2>/dev/null || true
}

TASK_BIN="$(resolve_task)"
if [[ -z "$TASK_BIN" ]]; then
  echo '==> Installing go-task'
  sudo pacman -S --needed go-task
  TASK_BIN="$(resolve_task)"
fi

[[ -n "$TASK_BIN" ]] || {
  echo 'ERROR: go-task was installed but neither task nor go-task is executable' >&2
  exit 1
}

exec "$TASK_BIN" bootstrap

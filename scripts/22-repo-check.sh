#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

required=(shellcheck yamllint actionlint gitleaks git)
for cmd in "${required[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: missing '$cmd'. Run: task tools:install (or go-task tools:install on stock Arch)" >&2
    exit 1
  }
done

if command -v task >/dev/null 2>&1; then
  TASK_BIN="$(command -v task)"
elif command -v go-task >/dev/null 2>&1; then
  TASK_BIN="$(command -v go-task)"
else
  echo "ERROR: missing Task runner. Install the Arch package 'go-task'." >&2
  exit 1
fi

echo '==> Bash syntax'
while IFS= read -r -d '' f; do bash -n "$f"; done < <(find scripts -type f -name '*.sh' -print0)
bash -n bootstrap.sh

echo '==> ShellCheck'
shellcheck scripts/*.sh bootstrap.sh

echo '==> YAML lint'
yamllint Taskfile.yml config .github/workflows

echo '==> GitHub Actions lint'
actionlint

echo '==> Taskfile parse'
"$TASK_BIN" --list >/dev/null

echo '==> Git whitespace/conflict-marker checks'
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
else
  echo 'NOTE not inside a Git worktree; skipping git diff --check'
fi

echo '==> Secret ignore policy'
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ./scripts/21-repo-secret-ignore-check.sh
else
  echo 'NOTE not inside a Git worktree; skipping git check-ignore assertions'
fi

echo '==> Secret scan'
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  gitleaks git --redact --no-banner .
else
  gitleaks dir --redact --no-banner .
fi

echo 'OK repository validation passed'

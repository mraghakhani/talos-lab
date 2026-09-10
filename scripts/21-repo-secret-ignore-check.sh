#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

patterns=(
  'config/lab.local.env'
  'state/generated/example.yaml'
  'infrastructure/talos/generated/controlplane.yaml'
  'talosconfig'
  'kubeconfig'
  'cluster.kubeconfig'
  'secrets/example.txt'
  'openbao/data/raft.db'
  'openbao/recovery/recovery.txt'
  'identity.agekey'
  'private.key'
)

failed=0
for path in "${patterns[@]}"; do
  if git check-ignore --no-index -q "$path"; then
    printf 'OK   ignored: %s\n' "$path"
  else
    printf 'FAIL not ignored: %s\n' "$path" >&2
    failed=1
  fi
done

if ((failed)); then
  echo "ERROR: secret/runtime ignore policy is incomplete" >&2
  exit 1
fi

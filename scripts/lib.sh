#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${LAB_ENV_FILE:-$PROJECT_ROOT/config/lab.env}"
LOCAL_ENV_FILE="${LAB_LOCAL_ENV_FILE:-$PROJECT_ROOT/config/lab.local.env}"
VERSIONS_FILE="${LAB_VERSIONS_FILE:-$PROJECT_ROOT/config/versions.yaml}"

if [[ ! -r "$ENV_FILE" ]]; then
  echo "ERROR: cannot read $ENV_FILE" >&2
  exit 1
fi

# Committed defaults first, optional machine-local overrides second.
# shellcheck disable=SC1090
source "$ENV_FILE"
if [[ -r "$LOCAL_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_ENV_FILE"
fi

# Cluster artifact versions are committed desired state. Allow an explicit process-level
# override for debugging, but do not duplicate them in lab.env/local.env.
if [[ -z "${TALOS_VERSION:-}" ]]; then
  command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required to read $VERSIONS_FILE" >&2; exit 1; }
  TALOS_VERSION="$(yq -r '.cluster.talos' "$VERSIONS_FILE")"
fi

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

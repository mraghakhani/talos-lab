#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOOLS_FILE="$PROJECT_ROOT/config/tools.yaml"
VERSIONS_FILE="$PROJECT_ROOT/config/versions.yaml"

command -v yq >/dev/null 2>&1 || {
  echo "ERROR: yq is required. Run the host bootstrap first." >&2
  exit 1
}

resolve_command() {
  local candidate
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

missing=0
printf '%-16s %-8s %s\n' COMMAND STATUS PATH
printf '%-16s %-8s %s\n' '----------------' '--------' '----'
while IFS=$'\t' read -r label candidates; do
  # shellcheck disable=SC2206
  candidate_array=($candidates)
  if path="$(resolve_command "${candidate_array[@]}" 2>/dev/null)"; then
    printf '%-16s %-8s %s\n' "$label" OK "$path"
  else
    printf '%-16s %-8s %s\n' "$label" MISSING '-'
    missing=1
  fi
done < <(yq -r '.commands[] | [.name, (.alternatives | join(" "))] | @tsv' "$TOOLS_FILE")

echo
echo "Desired cluster versions:"
printf '  Talos:       %s\n' "$(yq -r '.cluster.talos' "$VERSIONS_FILE")"
printf '  Kubernetes:  %s\n' "$(yq -r '.cluster.kubernetes' "$VERSIONS_FILE")"

echo
echo "Installed versions (best effort):"

TASK_BIN="$(resolve_command task go-task 2>/dev/null || true)"
if [[ -n "$TASK_BIN" ]]; then
  printf '\n[task]\n'
  "$TASK_BIN" --version 2>&1 | head -n 4 || true
fi

for spec in \
  'kubectl:kubectl version --client=true' \
  'helm:helm version --short' \
  'talosctl:talosctl version --client' \
  'cilium:cilium version --client' \
  'argocd:argocd version --client' \
  'argo:argo version --short' \
  'sops:sops --version' \
  'cosign:cosign version' \
  'kubeconform:kubeconform -v' \
  'gitleaks:gitleaks version'; do
  cmd="${spec%%:*}"
  check="${spec#*:}"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '\n[%s]\n' "$cmd"
    bash -lc "$check" 2>&1 | head -n 4 || true
  fi
done

# talosctl is tightly coupled to the Talos version we are bootstrapping.
desired_talos="$(yq -r '.cluster.talos' "$VERSIONS_FILE")"
if command -v talosctl >/dev/null 2>&1; then
  installed_talos="$(talosctl version --client 2>/dev/null | awk '/Tag:/ {print $2; exit}')"
  if [[ -n "$installed_talos" && "$installed_talos" != "$desired_talos" ]]; then
    echo >&2
    echo "ERROR: talosctl version mismatch: installed=$installed_talos desired=$desired_talos" >&2
    missing=1
  fi
fi

# kubectl may be +/- one minor relative to kube-apiserver. Warn outside that range.
if command -v kubectl >/dev/null 2>&1; then
  installed_k8s="$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion // empty' || true)"
  desired_k8s="$(yq -r '.cluster.kubernetes' "$VERSIONS_FILE")"

  installed_major=''
  installed_minor=''
  desired_major=''
  desired_minor=''

  if [[ "$installed_k8s" =~ ^v?([0-9]+)\.([0-9]+)\. ]]; then
    installed_major="${BASH_REMATCH[1]}"
    installed_minor="${BASH_REMATCH[2]}"
  fi
  if [[ "$desired_k8s" =~ ^v?([0-9]+)\.([0-9]+)\. ]]; then
    desired_major="${BASH_REMATCH[1]}"
    desired_minor="${BASH_REMATCH[2]}"
  fi

  if [[ -n "$installed_major" && -n "$desired_major" ]]; then
    delta=$(( installed_minor - desired_minor ))
    (( delta < 0 )) && delta=$(( -delta ))
    if [[ "$installed_major" != "$desired_major" || $delta -gt 1 ]]; then
      echo >&2
      echo "WARN: kubectl $installed_k8s is outside the supported +/-1 minor skew for Kubernetes $desired_k8s" >&2
    elif [[ "$installed_k8s" != "$desired_k8s" ]]; then
      echo
      echo "NOTE: kubectl $installed_k8s is within the supported +/-1 minor skew for Kubernetes $desired_k8s."
    fi
  fi
fi

if ((missing)); then
  echo >&2
  echo "ERROR: workstation tooling is incomplete or version-incompatible." >&2
  echo "Run: task tools:install  (or: go-task tools:install on stock Arch)" >&2
  exit 1
fi

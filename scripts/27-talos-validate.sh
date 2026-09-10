#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd talosctl
need_cmd yq

GENERATED="$PROJECT_ROOT/infrastructure/talos/generated"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"
failures=0

[[ -s "$GENERATED/secrets.yaml" ]] || die "Talos secrets missing; run task talos:generate"
[[ -s "$GENERATED/talosconfig" ]] || die "talosconfig missing; run task talos:generate"

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  cfg="$GENERATED/${name}.yaml"
  if [[ ! -s "$cfg" ]]; then
    echo "FAIL missing $cfg" >&2
    ((failures+=1))
    continue
  fi

  if talosctl validate --config "$cfg" --mode metal --strict >/dev/null; then
    ok "$name configuration validates in metal mode"
  else
    echo "FAIL $name configuration validation failed" >&2
    ((failures+=1))
  fi

done < <(yq -r '.nodes[].name' "$NODES_FILE")

# Guard against accidentally setting proxy values through deprecated machine.env.
# An empty legacy field emitted by a generator is harmless; non-empty values are not.
for cfg in "$GENERATED"/talos-*.yaml; do
  if yq -e 'select(.machine.env != null and (.machine.env | length > 0))' "$cfg" >/dev/null 2>&1; then
    echo "FAIL $cfg contains non-empty deprecated machine.env" >&2
    ((failures+=1))
  fi

  if ! grep -q 'kind: EnvironmentConfig' "$cfg"; then
    echo "FAIL EnvironmentConfig is missing from $cfg" >&2
    ((failures+=1))
  fi
done

if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  for sensitive in \
    infrastructure/talos/generated/secrets.yaml \
    infrastructure/talos/generated/talosconfig \
    infrastructure/talos/generated/talos-cp-01.yaml; do
    if ! git -C "$PROJECT_ROOT" check-ignore -q "$sensitive"; then
      echo "FAIL sensitive generated path is not gitignored: $sensitive" >&2
      ((failures+=1))
    fi
  done
fi

(( failures == 0 )) || die "$failures Talos configuration validation checks failed"
ok "Talos generated configuration passed validation and secret-path checks"

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

need_cmd envsubst
need_cmd yq

PATCH_SRC="$PROJECT_ROOT/infrastructure/talos/patches"
PATCH_OUT="$PROJECT_ROOT/state/rendered/talos"
NODE_OUT="$PATCH_OUT/nodes"
NODES_FILE="$PROJECT_ROOT/config/nodes.yaml"

mkdir -p "$NODE_OUT"

# Restrict envsubst to variables owned by this renderer. Talos patch documents
# use keys such as `$patch`; unrestricted envsubst would interpret `$patch` as
# an environment variable and corrupt the YAML into `: delete`.
# shellcheck disable=SC2016  # Literal ${VAR} tokens are intentionally passed to envsubst.
ENV_SUBST_VARS='${POD_CIDR} ${SERVICE_CIDR} ${LAB_NETWORK} ${PROXY_SCHEME} ${PROXY_HOST} ${PROXY_PORT} ${LAB_DOMAIN}'

for role in common controlplane worker; do
  src="$PATCH_SRC/${role}.yaml.tmpl"
  dst="$PATCH_OUT/${role}.yaml"
  [[ -f "$src" ]] || die "missing Talos patch template: $src"
  envsubst "$ENV_SUBST_VARS" < "$src" > "$dst"
  yq eval-all '.' "$dst" >/dev/null
  log "rendered and validated ${dst#"$PROJECT_ROOT"/}"
done

# Node patches use the permanent libvirt MAC as the network selector. This avoids
# coupling Talos configuration to predictable-interface names such as ens3.
while IFS=$'\t' read -r name role ip mac; do
  [[ -n "$name" ]] || continue
  outfile="$NODE_OUT/${name}.yaml"

  cat > "$outfile" <<YAML
apiVersion: v1alpha1
kind: LinkAliasConfig
name: ${TALOS_LINK_ALIAS}
selector:
  match: 'mac(link.permanent_addr) == "${mac}"'
---
apiVersion: v1alpha1
kind: LinkConfig
name: ${TALOS_LINK_ALIAS}
up: true
---
apiVersion: v1alpha1
kind: DHCPv4Config
name: ${TALOS_LINK_ALIAS}
clientIdentifier: mac
ignoreHostname: true
---
apiVersion: v1alpha1
kind: HostnameConfig
hostname: ${name}
auto: off
YAML

  if [[ "$role" == "controlplane" ]]; then
    cat >> "$outfile" <<YAML
---
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: ${K8S_API_VIP}
link: ${TALOS_LINK_ALIAS}
YAML
  fi

  log "rendered ${outfile#"$PROJECT_ROOT"/} ($role, $ip, $mac)"
done < <(yq -r '.nodes[] | [.name, .role, .ip, .mac] | @tsv' "$NODES_FILE")

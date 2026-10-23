#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# Read-only Kubernetes-side snapshot: nodes, pods and the most recent events.
# First stop for "why is this pod not Ready".

need_cmd kubectl

[[ -s "$KUBECONFIG" ]] || die "kubeconfig missing; run task talos:kubeconfig"
export KUBECONFIG

echo "== Nodes"
kubectl get nodes -o wide
echo
echo "== Pods"
kubectl get pods -A
echo
echo "== Recent events"
kubectl get events -A --sort-by=.lastTimestamp | tail -n 25

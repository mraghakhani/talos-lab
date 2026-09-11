# Architecture Decisions

Short decision log for agents.

## ADR-001 — QEMU/KVM/libvirt

**Decision:** use QEMU/KVM managed by libvirt.

**Why:**
- native Linux virtualization
- reproducible domain/network/storage definitions
- strong CLI automation
- realistic multi-node behavior
- no desktop virtualization dependency

## ADR-002 — Taskfile instead of Makefile

**Decision:** Taskfile is the repository's operator interface.

**Why:**
- user preference
- readable task dependencies
- YAML-native
- clearer operational intent than Make targets

## ADR-003 — Six-node topology

**Decision:** three control planes + three workers.

**Why:**
- realistic etcd quorum
- control-plane failure exercises
- workload scheduling exercises
- dedicated workers for RabbitMQ/autoscaling/storage experiments

## ADR-004 — Host proxy is mandatory for node external access

**Decision:** Talos nodes use `http://192.168.231.1:10808`.

**Why:** external registry/network access is intentionally routed through the host proxy.

**Consequence:** image pre-pull and retry workflows are first-class operational features.

## ADR-005 — Cilium, no Flannel, no kube-proxy

**Decision:** Cilium is the CNI and service datapath.

**Why:**
- eBPF datapath
- kube-proxy replacement
- Hubble observability
- later Gateway API / LoadBalancer IPAM / L2 announcements
- network-policy capabilities

## ADR-006 — Core connectivity suite is authoritative

**Decision:** internal Cilium connectivity is the required gate.

**Why:** direct pod Internet access is not part of the baseline lab contract.

## ADR-007 — GitOps split

**Decision:** bootstrap infrastructure stays here; day-2 Kubernetes desired state lives in `talos-gitops`.

**Why:** it creates a clean handoff from machine bootstrap to continuous reconciliation.

## ADR-008 — Secret values never belong in Git

**Decision:** generated PKI, kubeconfig, talosconfig, deploy private keys, and future application secrets are local-only or external-secret-manager material.

**Planned runtime secret system:** OpenBao + External Secrets Operator.

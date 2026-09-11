# AI Handoff

Use this file when starting a fresh AI-agent session.

## One-paragraph context

This repository builds a six-node Talos Kubernetes lab on a CachyOS laptop using QEMU/KVM/libvirt. The libvirt subnet is `192.168.231.0/24`, the API VIP is `192.168.231.10`, control planes are `.11-.13`, and workers are `.21-.23`. All Talos nodes must reach external registries through the host HTTP proxy at `192.168.231.1:10808`. Talos is `v1.14.0`, Kubernetes is `v1.37.0`, and Cilium `1.20.1` provides CNI, kube-proxy replacement, and Hubble. The six nodes are Ready and the proxy-aware Cilium core verification passes. Day-2 platform resources are now owned by the separate `talos-gitops` repository managed by Argo CD.

## First commands for an agent

```bash
git status
task repo:check
task vm:status
task talos:status
task cilium:status
```

Do not mutate anything until current state is understood.

## Known historical traps

- ShellCheck is enforced, including informational/style findings in some scripts.
- YAML anchors cannot cross `---` document boundaries.
- Talos 1.14 uses multi-document config; do not assume old v1alpha1 paths.
- Do not mix old v1alpha1 fields with new Talos config documents.
- Talos endpoints can proxy requests; direct node health checks should set both endpoint and node to the same IP.
- A successful `talosctl bootstrap` RPC alone does not prove etcd initialized.
- Registry pulls can transiently fail with `403`; pre-pull with retries.
- Do not reboot a first control plane that is waiting for bootstrap after a failed first bootstrap unless you understand the resulting state.
- Cilium connectivity tests need temporary privileged Pod Security labels.
- The full Cilium external-egress suite is not authoritative in this proxy-constrained environment.

## Current ownership boundary

If the task is about:
- libvirt
- VM lifecycle
- Talos
- etcd bootstrap
- Kubernetes foundation
- Cilium foundation

work here.

If the task is about:
- Argo CD Applications
- Gateway API
- TLS/cert-manager
- External Secrets
- OpenBao integration
- RabbitMQ
- KEDA
- monitoring/logging
- Argo Workflows
- Go demo applications

work in `talos-gitops`.

## Preferred agent output

For implementation work:
- modify files directly when possible
- keep diffs small
- add Taskfile targets for operator actions
- run validation
- summarize changed files and next command
- do not provide giant speculative redesigns when a focused patch solves the issue

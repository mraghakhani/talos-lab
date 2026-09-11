# AGENTS.md

This file is the operating contract for AI agents working in this repository.

## Mission

`talos-lab` owns the reproducible infrastructure foundation for the local Kubernetes lab:

- CachyOS / Arch Linux host prerequisites
- QEMU/KVM/libvirt networking, storage, and VM lifecycle
- Talos Linux machine configuration and bootstrap
- Kubernetes control-plane bring-up
- Cilium CNI / kube-proxy replacement / Hubble
- workstation-side validation and recovery tooling

This repository does **not** own day-2 Kubernetes platform applications such as cert-manager,
External Secrets, RabbitMQ, KEDA, observability, or application deployments. Those belong in
the separate `talos-gitops` repository after Argo CD bootstrap.

## Current topology

Host-side:
- Hypervisor: QEMU/KVM/libvirt
- Host OS: CachyOS / Arch Linux
- Architecture: amd64
- Host HTTP proxy: `http://127.0.0.1:10808`
- VM-reachable proxy: `http://192.168.231.1:10808`
- libvirt network: `192.168.231.0/24`
- libvirt bridge: `virbr231`
- Kubernetes API VIP: `192.168.231.10`

Nodes:

| Node | Role | IP |
|---|---|---|
| talos-cp-01 | controlplane | 192.168.231.11 |
| talos-cp-02 | controlplane | 192.168.231.12 |
| talos-cp-03 | controlplane | 192.168.231.13 |
| talos-worker-01 | worker | 192.168.231.21 |
| talos-worker-02 | worker | 192.168.231.22 |
| talos-worker-03 | worker | 192.168.231.23 |

Pinned foundation versions at the current milestone:
- Talos: `v1.14.0`
- Kubernetes: `v1.37.0`
- Cilium: `1.20.1`

## Non-negotiable engineering rules

1. **Reproducible first.**
   - Prefer declarative config, scripts, and Taskfile targets.
   - Do not make manual commands the source of truth.
   - If a one-off recovery command is necessary, follow it with a reproducible task/script change.

2. **Taskfile, not Makefile.**
   - New operational entry points belong in `Taskfile.yml`.
   - Scripts should live under `scripts/` and be called by Taskfile targets.

3. **Idempotency matters.**
   - Re-running a task should converge or safely report existing state.
   - Destructive tasks must be explicit in naming, e.g. `*:destroy`, `*:recreate`, `*:force`.

4. **Proxy awareness is mandatory.**
   - Talos/system image access depends on the host proxy.
   - Never assume nodes or pods have unrestricted direct Internet access.
   - Image-heavy workflows should pre-pull with retries where practical.

5. **Never weaken security globally to fix a test.**
   - Scope Pod Security exemptions to temporary test namespaces.
   - Never disable SSH host verification globally.
   - Never commit private keys, kubeconfig, talosconfig, generated PKI, or secret values.

6. **Generated Talos identity must remain stable.**
   - Reuse the existing Talos secrets bundle when regenerating configs.
   - Do not casually delete generated cluster identity artifacts unless intentionally rebuilding the cluster.

7. **Bootstrap is special.**
   - `talosctl bootstrap` is a one-cluster initialization step.
   - Do not bootstrap again if etcd is healthy and already initialized.
   - A local marker file is not sufficient proof; verify actual etcd state.

8. **Direct node checks are preferred for Talos health.**
   - For critical diagnostics, use the target node as both `--endpoints` and `--nodes`.
   - This avoids another control plane proxying the request and masking a dead node.

9. **Cilium core verification is the release gate.**
   - `task cilium:verify` is the required internal datapath check.
   - `task cilium:verify:full` is diagnostic because direct pod Internet access is intentionally constrained.

10. **Keep repository ownership boundaries clean.**
    - This repo bootstraps infrastructure and Cilium.
    - Kubernetes add-ons and apps belong in `talos-gitops`.

## Before making changes

Read:
1. `TODO.md`
2. `docs/CURRENT_STATE.md`
3. `docs/ARCHITECTURE.md`
4. `docs/OPERATIONS.md`
5. `docs/DECISIONS.md`

Then inspect the relevant Taskfile target and script before editing.

## Required validation

At minimum after repository changes:

```bash
task repo:check
```

For infrastructure changes, also run the smallest relevant validation target, for example:

```bash
task preflight
task vm:plan
task talos:validate
task talos:secure:check
task cilium:status
task cilium:verify
```

Do not claim a change works unless its relevant validation passed or explicitly state what was not tested.

## Editing conventions

- Bash: `set -euo pipefail`
- Shared helpers belong in `scripts/lib.sh`
- Use `need_cmd`, `log`, `ok`, `note`, `warn`, `die` helpers where available
- Quote variables
- Keep ShellCheck clean
- Keep YAML lint clean
- Avoid clever shell pipelines when a readable `if` block is safer
- Prefer repo-relative state and config paths
- Keep rendered/generated artifacts out of Git unless they are intentionally source-of-truth files

## Destructive operations

Treat these as dangerous:
- VM destroy/recreate
- storage pool destroy
- network destroy/recreate
- deleting Talos identity/secrets
- wiping `/dev/vda`
- re-bootstrap
- forced VM power-off

`task vm:stop:force` is equivalent to pulling power. It preserves VM definitions/disks but is not a graceful shutdown.

An agent must clearly state the blast radius before changing or invoking destructive behavior.

## Expected agent behavior

When asked to implement something:
1. Inspect existing patterns first.
2. Prefer extending them over inventing a parallel framework.
3. Make the change reproducible.
4. Add/adjust Taskfile targets if operators need a command.
5. Update docs if operational behavior changes.
6. Run validation.
7. Report exact files changed, commands run, and any unresolved risk.

Do not ask for confirmation for routine, reversible implementation details. Ask only when a choice changes architecture, destroys state, or needs a credential/value not already present.

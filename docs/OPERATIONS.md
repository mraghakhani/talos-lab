# Operations Runbook

Use Taskfile targets as the operational API. Prefer tasks over direct commands.

## Validate repository

```bash
task repo:check
```

## Host / libvirt

```bash
task preflight
task network:up
task storage:up
task vm:plan
task vm:create
task vm:status
```

## VM lifecycle

Start all VMs using the repository's idempotent start task/script if present.

Hard power-off:

```bash
task vm:stop:force
```

This is equivalent to pulling power. It is not the normal shutdown path.

A graceful shutdown task should be added and preferred for routine operations.

## Talos

Maintenance-mode checks:

```bash
task talos:maintenance:check
```

Generate and validate:

```bash
task talos:generate
task talos:validate
```

Apply initial config:

```bash
task talos:apply
```

Post-install direct health:

```bash
task talos:secure:check
```

Detach ISO:

```bash
task vm:detach-iso
```

Pre-pull required images:

```bash
task talos:images:prepull
```

Bootstrap only when the first control plane is explicitly waiting to bootstrap and etcd has not already formed:

```bash
task talos:bootstrap
```

Never use a stale local marker as the only proof that bootstrap succeeded.

## etcd diagnostics

Directly against cp-01:

```bash
export TALOSCONFIG="$PWD/infrastructure/talos/generated/talosconfig"

talosctl \
  --endpoints 192.168.231.11 \
  --nodes 192.168.231.11 \
  service etcd

talosctl \
  --endpoints 192.168.231.11 \
  --nodes 192.168.231.11 \
  etcd members
```

If etcd is waiting to join the cluster on the very first member, bootstrap may be required.
If etcd is already healthy, do not bootstrap again.

## Kubernetes

```bash
export KUBECONFIG="$PWD/infrastructure/talos/generated/kubeconfig"

kubectl get nodes -o wide
kubectl get pods -A
```

## Cilium

```bash
task cilium:status
task cilium:verify
task cilium:hubble:status
```

Full diagnostic suite:

```bash
task cilium:verify:full
```

The full suite is not a release gate in the current proxy-constrained lab.

## Proxy troubleshooting

Host:

```bash
curl -vIL \
  --proxy http://127.0.0.1:10808 \
  https://registry.k8s.io/v2/
```

Talos nodes should use:

```text
http://192.168.231.1:10808
```

If a system image pull failed transiently, pre-pull it into the correct Talos namespace rather than repeatedly rebooting nodes.

## Recovery principle

Diagnose from the lowest layer upward:

1. VM power state
2. libvirt network/lease
3. Talos API
4. Talos services
5. etcd
6. Kubernetes control plane
7. node readiness
8. Cilium
9. workloads

Do not debug Kubernetes objects while the VM or Talos layer is unhealthy.

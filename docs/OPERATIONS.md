# Operations Runbook

Use Taskfile targets as the operational API. Prefer tasks over direct commands.

## Validate repository

```bash
task repo:check
```

## Operator shell environment (mise)

`mise.toml` at the repo root exports `KUBECONFIG` and `TALOSCONFIG` automatically
when the shell enters this directory (mise is preinstalled on the host and
`mise activate` is wired into the zshrc by Omarchy). First time in a clone, run:

```bash
mise trust
```

Behavior:

- `KUBECONFIG` points only at the lab kubeconfig, so `kubectl` in this directory
can never reach another cluster by accident.
- Scripts do not depend on mise: `scripts/lib.sh` + `config/lab.env` remain the
source of truth and work in any shell.
- The proxy is deliberately not exported into the shell (it would break local
services such as the gitea remote without maintaining `NO_PROXY`); scripts read
the proxy from `config/lab.env` themselves.
- Machine-local overrides go in `mise.local.toml` (gitignored).

Taskfile.yml stays the task entry point; mise is only the shell environment.

## Host / libvirt

```bash
task preflight
task network:up
task storage:up
task vm:plan
task vm:create
task vm:status
```

When UFW is active, `task network:up` leaves it enabled and permits DHCP on the
lab bridge plus NTP/NTS egress (`UDP/123`, `TCP/4460`) from the lab subnet.
Empty leases indicate blocked DHCP. Talos stuck in `Booting` with `apid` waiting
for time sync indicates blocked NTP/NTS. Rerun `task network:up` in either case.

## Network addressing and firewall

Libvirt NAT network `192.168.231.0/24` on `virbr231`. Address plan (all reserved,
never hand out from DHCP):

| Range / address | Use |
|---|---|
| `192.168.231.1` | host gateway + VM-reachable proxy (`10808`) |
| `192.168.231.10` | Kubernetes API VIP |
| `192.168.231.11-13` | combined controlplane+worker nodes (talos-node-0[1-3]) |
| `192.168.231.200-220` | Cilium LB-IPAM pool (Gateway/LoadBalancer IPs) |
| `192.168.231.100-180` | libvirt DHCP (temporary VM boot only) |

The LB pool sits outside the DHCP range on purpose: Cilium L2-announces pool
IPs on `virbr231`; a DHCP overlap would cause duplicate-address conflicts.

Firewall (UFW) expectations on the host:

- `task network:up` permits DHCP (UDP 67/68) and NTP/NTS egress (UDP/123,
  TCP/4460) for the lab subnet while leaving UFW enabled.
- Inbound to VMs traverses libvirt NAT; no additional inbound rules are needed
  for the host-only network.
- Host services the VMs use: proxy `127.0.0.1:10808` (VMs reach it as
  `192.168.231.1:10808`), Gitea `3000` (HTTP) and `2222` (SSH).
- `task preflight` checks the critical paths; empty DHCP leases or Talos time
  sync stalls mean a rule is missing.


## VM lifecycle

Start all VMs using the repository's idempotent start task/script if present.

Hard power-off:

```bash
task vm:stop:force
```

This is equivalent to pulling power. It is not the normal shutdown path.

Use `task vm:stop` for routine shutdowns. It requests a clean OS-level shutdown
through the Talos API (`shutdown --force --wait=false`) and falls back to the
ACPI power button. Kubernetes cordon/drain is intentionally skipped: it cannot
complete on a pre-bootstrap node and would leave the guest half-shut-down.

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

On a slow link the first install takes many minutes: each node downloads the
Talos installer image before it writes anything to disk. Do **not** power off a
node in this window — an interrupted install leaves a blank disk and must be
re-applied. Watch progress with:

```bash
talosctl --talosconfig infrastructure/talos/generated/talosconfig dmesg --nodes <ip>
```

Day-2 machine-config changes on already-installed nodes use:

```bash
task talos:config:apply
```

It applies through the authenticated Talos API (no maintenance mode required).

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

Never use a stale local marker as the only proof that bootstrap succeeded. The bootstrap task checks live etcd membership first, refuses to bootstrap when any control plane has existing etcd member data, and writes the completion marker only after membership is reachable.

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

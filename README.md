# Talos Kubernetes Laptop Lab

A reproducible, production-shaped Kubernetes lab for a CachyOS/Arch Linux laptop using **QEMU + KVM + libvirt**, Talos Linux, Cilium, Argo CD/Workflows, OpenBao, External Secrets, RabbitMQ, KEDA, observability, and security policy enforcement.

The repository is intentionally automation-first:

- `Taskfile.yml` is the human-facing command interface.
- `config/` contains committed, non-secret desired infrastructure state.
- `libvirt/*.tmpl` contains reusable libvirt definitions.
- `scripts/` contains idempotent implementation logic.
- `state/` contains generated/downloaded runtime artifacts and is gitignored.
- Generated Talos secrets/configuration will be gitignored in the next milestone.

## Current topology

| Node | Role | IP | vCPU | RAM | OS disk | Data disk |
|---|---|---:|---:|---:|---:|---:|
| talos-cp-01 | control plane | 192.168.231.11 | 2 | 2560 MiB | 20 GiB | - |
| talos-cp-02 | control plane | 192.168.231.12 | 2 | 2560 MiB | 20 GiB | - |
| talos-cp-03 | control plane | 192.168.231.13 | 2 | 2560 MiB | 20 GiB | - |
| talos-worker-01 | worker | 192.168.231.21 | 4 | 4608 MiB | 30 GiB | 40 GiB |
| talos-worker-02 | worker | 192.168.231.22 | 4 | 4608 MiB | 30 GiB | 40 GiB |
| talos-worker-03 | worker | 192.168.231.23 | 4 | 4608 MiB | 30 GiB | 40 GiB |

Additional addresses:

- libvirt gateway / host from VMs: `192.168.231.1`
- Kubernetes API VIP: `192.168.231.10`
- DHCP dynamic pool: `192.168.231.100-180`
- future Cilium LoadBalancer pool: `192.168.231.200-220`
- Pod CIDR: `10.244.0.0/16`
- Service CIDR: `10.96.0.0/12`

Node addresses are deterministic DHCP reservations based on fixed MAC addresses in `config/nodes.yaml` and `config/lab.env`.

## Proxy model

The host proxy listens on port `10808`.

Host-side downloads use:

```text
http://127.0.0.1:10808
```

Talos VMs will use:

```text
http://192.168.231.1:10808
```

The lab explicitly verifies both paths before Talos configuration is applied. A proxy bound only to `127.0.0.1` will fail `task proxy:check:lab` by design.

## Version pinning

Talos is pinned in `config/lab.env`:

```text
TALOS_VERSION=v1.14.0
```

Do not replace this with `latest`. Upgrades will be explicit, reviewed changes to desired state.

The Talos ISO is downloaded through the host proxy and verified against the official release `sha256sum.txt` before it is copied into the libvirt storage pool.

## First-time host bootstrap

If Task is not installed yet:

```bash
./bootstrap.sh
```

Otherwise:

`host:install` uses Arch's `go-yq` package (the Mike Farah `yq` implementation used by the inventory scripts).

```bash
task host:install
task host:check
```

List all available tasks:

```bash
task --list
```

## Provisioning sequence

Run these in order. Do not jump directly to `infra:up` the first time; each boundary is an acceptance test.

### 1. Preflight

```bash
task preflight
```

This validates KVM/libvirt tooling and confirms `127.0.0.1:10808` can proxy registry traffic.

### 2. Create the isolated libvirt network

```bash
task network:up
task network:status
```

The rendered definition is written to:

```text
state/rendered/network.xml
```

### 3. Verify the proxy from the VM-facing address

```bash
task proxy:check:lab
```

This must succeed before continuing. If it fails while the host proxy test succeeds, the proxy is probably listening only on loopback.

### 4. Create the dedicated libvirt storage pool

```bash
task storage:up
task storage:status
```

The pool target is:

```text
/var/lib/libvirt/images/talos-lab
```

### 5. Download and verify the pinned Talos ISO

```bash
task image:download
```

The verified download cache remains under `state/downloads/` so destructive VM rebuilds do not force another internet download.

### 6. Create all six VMs

```bash
task vm:create
task vm:status
```

The VMs boot the Talos ISO into maintenance mode. Their OS disks are `vda`; worker data disks are `vdb`.

At this point **do not bootstrap Kubernetes manually**. The next milestone generates reproducible Talos machine configuration, including the Kubernetes API VIP, proxy/no-proxy environment, kube-proxy disablement for Cilium, install-disk configuration, and per-node application automation.

## Convenience tasks

Once the individual stages have been validated, the whole virtualization layer can be recreated with:

```bash
task infra:up
```

Inspect it with:

```bash
task infra:status
```

Destroy only lab-owned VMs, disks, storage pool, and network with:

```bash
task infra:destroy
```

The download cache remains intact.

## Source of truth

Change infrastructure here rather than editing libvirt objects by hand:

- `config/lab.env` — shared network, proxy, version and storage settings
- `config/nodes.yaml` — VM inventory/resources
- `libvirt/network.xml.tmpl` — network definition template
- `libvirt/pool.xml.tmpl` — storage-pool template

If a definition changes after a libvirt object already exists, recreate that object through its Task target rather than changing it manually.

## Planned next milestone

The next milestone will add:

```text
talos/
├── patches/
│   ├── common.yaml
│   ├── controlplane.yaml
│   └── worker.yaml
└── generated/           # gitignored secrets and rendered machine config
```

and tasks roughly shaped as:

```text
task talos:generate
task talos:apply
task talos:bootstrap
task talos:kubeconfig
task talos:status
```

After that, Cilium becomes the first Kubernetes platform component.

## Safe VM provisioning checkpoint

Before defining any VM domains, verify the pinned ISO and inspect the complete desired topology:

```bash
task image:download
task image:status
task vm:plan
```

`task vm:plan` is non-destructive. It prints all six nodes, their IP/MAC/resource allocation, total virtual capacity, API VIP, proxy endpoint, and validates that the libvirt network, pool, and verified Talos ISO exist.

Only after the plan is clean should you run:

```bash
task vm:create
```

# Talos Kubernetes Laptop Lab

A reproducible, production-shaped Kubernetes lab for a CachyOS/Arch Linux laptop using **QEMU + KVM + libvirt**, Talos Linux, Cilium, Argo CD/Workflows, OpenBao, External Secrets, RabbitMQ, KEDA, observability, and security policy enforcement.

The repository is intentionally automation-first:

- `Taskfile.yml` is the human-facing command interface.
- `config/` contains committed, non-secret desired infrastructure state.
- `infrastructure/libvirt/*.tmpl` contains reusable libvirt definitions.
- `scripts/` contains idempotent implementation logic.
- `state/` contains generated/downloaded runtime artifacts and is gitignored.
- Generated Talos secrets/configuration will be gitignored in the next milestone.

## Current topology

| Node | Role | IP | vCPU | RAM | OS disk | Data disk |
|---|---|---:|---:|---:|---:|---:|
| talos-cp-01 | control plane | 192.168.231.11 | 2 | 2560 MiB | 20 GiB | - |
| talos-cp-02 | control plane | 192.168.231.12 | 2 | 2560 MiB | 20 GiB | - |
| talos-cp-03 | control plane | 192.168.231.13 | 2 | 2560 MiB | 20 GiB | - |
| talos-worker-01 | worker | 192.168.231.21 | 4 | 4608 MiB | 20 GiB | 30 GiB |
| talos-worker-02 | worker | 192.168.231.22 | 4 | 4608 MiB | 20 GiB | 30 GiB |
| talos-worker-03 | worker | 192.168.231.23 | 4 | 4608 MiB | 20 GiB | 30 GiB |

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

Talos and Kubernetes are pinned in `config/versions.yaml`:

```yaml
cluster:
  talos: v1.14.0
  kubernetes: v1.37.0
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

When overlaying an updated archive onto an older checkout, run the safe layout migration once:

```bash
task repo:migrate-layout
```

It removes the former root `libvirt/` directory only after confirming its templates match the new `infrastructure/libvirt/` copies.

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

- `config/lab.env` — shared network, proxy and storage settings
- `config/versions.yaml` — pinned cluster/platform component versions
- `config/tools.yaml` — workstation CLI/package inventory
- `config/nodes.yaml` — VM inventory/resources
- `infrastructure/libvirt/network.xml.tmpl` — network definition template
- `infrastructure/libvirt/pool.xml.tmpl` — storage-pool template

If a definition changes after a libvirt object already exists, recreate that object through its Task target rather than changing it manually.


## Repository safety and developer tooling

Install the optional-but-recommended workstation Kubernetes/GitOps/security CLIs:

```bash
task tools:install
task tools:check

# Stock Arch installs the executable as `go-task`; if you do not have a
# shell alias named `task`, use `go-task` for the same commands.
```

Before every push, run:

```bash
task repo:check
```

Optionally enforce the same gate before every local commit:

```bash
task repo:hooks:install
```

The repository gate performs Bash syntax checks, ShellCheck, YAML linting, GitHub Actions linting, Taskfile parsing, Git whitespace checks, secret-ignore assertions, and a gitleaks scan. The same validation runs in `.github/workflows/validate.yml` on pushes and pull requests.

Generated Talos configuration, kubeconfigs, OpenBao runtime/recovery material, age identities, private keys, state, downloads, and machine-local overrides are gitignored. Encrypted SOPS documents may be committed later by design; the private age identity may not.

See `docs/repository.md` for the GitHub/Gitea remote model and branch-protection guidance.

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

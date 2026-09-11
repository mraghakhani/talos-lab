# Current State

Last known-good milestone from the lab build.

## Host

- OS: CachyOS / Arch Linux
- CPU virtualization: Intel VT-x / KVM
- Hypervisor: QEMU/KVM/libvirt
- Architecture: amd64
- Host LAN address during initial build: `192.168.0.161/24`
- Host-side proxy: `127.0.0.1:10808`
- VM-reachable proxy: `192.168.231.1:10808`

## libvirt

- Network name: `talos-lab`
- Bridge: `virbr231`
- Subnet: `192.168.231.0/24`
- Bridge IP: `192.168.231.1`
- Kubernetes API VIP: `192.168.231.10`
- Storage pool: `talos-lab`

## Nodes

| Name | Role | IP | vCPU | RAM | OS disk | data disk |
|---|---|---:|---:|---:|---:|---:|
| talos-cp-01 | controlplane | 192.168.231.11 | 2 | 2560 MiB | 20 GiB | - |
| talos-cp-02 | controlplane | 192.168.231.12 | 2 | 2560 MiB | 20 GiB | - |
| talos-cp-03 | controlplane | 192.168.231.13 | 2 | 2560 MiB | 20 GiB | - |
| talos-worker-01 | worker | 192.168.231.21 | 4 | 4608 MiB | 20 GiB | 30 GiB |
| talos-worker-02 | worker | 192.168.231.22 | 4 | 4608 MiB | 20 GiB | 30 GiB |
| talos-worker-03 | worker | 192.168.231.23 | 4 | 4608 MiB | 20 GiB | 30 GiB |

## Cluster

- Talos: `v1.14.0`
- Kubernetes: `v1.37.0`
- Cilium: `1.20.1`
- Three etcd voting members
- Six Kubernetes nodes are Ready
- Flannel disabled
- kube-proxy disabled
- Cilium provides CNI + kube-proxy replacement
- Hubble Relay/UI enabled

## Cilium verification model

`task cilium:verify`
- required acceptance gate
- internal cluster datapath
- skips direct pod-to-world/pod-to-CIDR scenarios
- Hubble flow validation disabled for this gate
- passes

`task cilium:verify:full`
- diagnostic only
- can fail in this lab because:
  - ordinary pods do not automatically inherit the host HTTP proxy
  - public external test endpoints may reject requests
  - Hubble flow validation can observe translated backend IPs instead of service VIPs

Do not treat failure of the full suite as proof that the cluster datapath is broken if the core suite passes.

## Repository boundary

This repo ends at:
- host/libvirt
- Talos
- Kubernetes bootstrap
- Cilium/Hubble foundation

The following now belong to `talos-gitops`:
- Argo CD-managed platform resources
- Gateway API exposure
- cert-manager
- External Secrets
- OpenBao integration
- observability
- RabbitMQ
- KEDA
- Argo Workflows
- application workloads

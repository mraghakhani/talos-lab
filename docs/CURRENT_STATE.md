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
| talos-node-01 | controlplane | 192.168.231.11 | 4 | 8192 MiB | 40 GiB | 20 GiB |
| talos-node-02 | controlplane | 192.168.231.12 | 4 | 8192 MiB | 40 GiB | 20 GiB |
| talos-node-03 | controlplane | 192.168.231.13 | 4 | 8192 MiB | 40 GiB | 20 GiB |

All three nodes are combined controlplane+worker machines (Talos control-plane
nodes are schedulable by default). Data disks are reserved for future
Rook-Ceph OSDs.

## Cluster

- Talos: `v1.14.4`
- Kubernetes: `v1.37.0`
- Cilium: `1.20.1`
- Three etcd voting members
- Three combined Kubernetes nodes are Ready (scheduled workloads land on the control-plane machines)
- Flannel disabled
- kube-proxy disabled
- Cilium provides CNI + kube-proxy replacement
- Hubble Relay/UI enabled
- cert-manager: `1.21.2` (Helm, own CRDs)
- Internal CA: `lab-selfsigned` -> `lab-ca` root (see ADR-009)
- Argo CD UI: `https://argocd.lab.example.com` via Gateway on
  `192.168.231.201`, TLS terminated at Envoy, plaintext backend
- Cilium LB-IPAM pool: `192.168.231.200-220`, L2-announced on `virbr231`

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

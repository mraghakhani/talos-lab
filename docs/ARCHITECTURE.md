# Architecture

## High-level layout

```text
CachyOS laptop
├── libvirt / QEMU / KVM
├── xray HTTP proxy :10808
├── virbr231 192.168.231.1/24
└── six Talos VMs
    ├── cp-01 192.168.231.11
    ├── cp-02 192.168.231.12
    ├── cp-03 192.168.231.13
    ├── worker-01 192.168.231.21
    ├── worker-02 192.168.231.22
    └── worker-03 192.168.231.23
```

Kubernetes API endpoint:

```text
https://192.168.231.10:6443
```

## Networking

The libvirt network is isolated from the physical LAN and gives the lab a stable address plan.

```text
VMs 192.168.231.0/24
        |
     virbr231
        |
192.168.231.1 host
        |
   host networking
```

Talos nodes use:

```text
http://192.168.231.1:10808
```

for external image/registry access.

The host itself uses:

```text
http://127.0.0.1:10808
```

## Kubernetes networking

Cilium is the only intended cluster networking implementation.

Design:
- Flannel removed
- kube-proxy disabled
- Cilium kube-proxy replacement enabled
- VXLAN tunneling for pod routing
- Hubble enabled for observability
- KubePrism `localhost:7445` used for Cilium bootstrap API access

Do not introduce another CNI.

## Storage

Control planes:
- OS disk on `/dev/vda`

Workers:
- OS disk on `/dev/vda`
- additional data disk on `/dev/vdb`

The worker data disks are reserved for later Kubernetes storage experiments.

## Repository split

`talos-lab`:
- imperative bootstrap expressed reproducibly
- host/hypervisor/Talos/Cilium

`talos-gitops`:
- declarative Kubernetes desired state
- reconciled by Argo CD

This separation is intentional. Do not move libvirt/Talos lifecycle into Argo CD.
Do not install day-2 Kubernetes platform components manually from `talos-lab`.

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

## ADR-009 — cert-manager with internal CA; TLS terminates at Gateway

**Decision:** certificates come from a two-stage internal CA: `lab-selfsigned`
(self-signed ClusterIssuer) issues the `lab-ca` root (ECDSA P-256, 10 years,
secret `lab-ca-key-pair`), and the `lab-ca` ClusterIssuer issues leaf
certificates for lab services. TLS terminates at the Cilium Gateway (Envoy);
backends receive plaintext. Argo CD serves insecure on 8080 behind its own
Gateway on `192.168.231.201`.

**Why:** the lab sits behind a host-only NAT with no inbound port 80/443, so
HTTP-01 is impossible and Let's Encrypt cannot validate. The real DNS zone
(ArvanCloud) has no cert-manager DNS-01 provider. An internal CA gives real
certificate automation and browser trust without external dependencies.

**Consequences:** the CA root must be trusted on operator workstations
(`sudo trust anchor`). Leaf lifetime is 90 days and renews automatically.
Rotating the root means re-issuing every leaf. The CA secret lives only in the
cluster; losing `lab-ca-key-pair` without a backup invalidates all leaves.

## ADR-010 — Three schedulable control-plane nodes replace the six-node topology

**Decision:** the lab converges on three nodes (`talos-node-01..03`, IPs
`192.168.231.11-13`), each a combined control-plane + worker node that stays
schedulable, sized 4 vCPU / 8 GiB RAM /
40 GiB OS disk / 20 GiB data disk. The three worker VMs are removed.

Schedulability is not automatic: `talosctl gen config` registers the
`node-role.kubernetes.io/control-plane:NoSchedule` taint on control-plane
machines. `infrastructure/talos/patches/controlplane.yaml.tmpl` removes it
(`KubeNodeConfig.taints` with `$patch: delete`) so regular workloads — Cilium
tests, hubble, GitOps apps — can run on every node.

**Why:** 6 x 2.5 GiB was too tight for the Ceph learning goal (each OSD wants
2-3 GiB). 3 x 8 GiB gives OSD headroom, and three nodes keep fault tolerance:
etcd raft majority survives one node loss, and a Ceph pool with
`size=3, min_size=2` does the same.

**Consequences:** two simultaneous node losses kill both etcd and Ceph —
accepted for a lab. Control-plane workloads now share CPU/RAM with system
components; resource requests must stay modest. Rebuild requires
`vm:destroy` + recreate + re-bootstrap; captured image stores seed the new
nodes (ADR-011).

## ADR-011 — Image stores are captured via the Talos API and re-seeded offline

**Decision:** before tearing down the lab, `task images:backup` records
per-node image inventories (`talosctl image list`, `cri` + `system`
namespaces) and captures the `/var/lib/containerd` store of every node that
adds images not covered by earlier captures (greedy cover) as one `.tar.gz`
per node via `talosctl copy`. Consistency is verified deterministically: the
containerd bolt metadata DB checksum must be identical before and after each
copy attempt (content store blobs are immutable). `task images:restore`
seeds a freshly installed node's store (STATE partition, before
talos:bootstrap) with the primary capture (richest node, metadata + blobs),
then merges content blobs from the other captures (digest-addressed,
copy-if-missing). Previous content is kept as `containerd.pre-seed` for
rollback.

**Why:** `talosctl` cannot export images directly (no `image export`/`push`,
no `exec`, no SSH on Talos), but `talosctl copy` streams a `.tar.gz` of any
node path over the API. Images already on the nodes are captured as-is —
never re-downloaded through the proxy.

**Consequences:** capture and restore must run on the same Talos version
(metadata DB is version-coupled). Images present only in secondary captures
have their layer blobs seeded but not their metadata; at first pod-schedule
only the manifest/config is fetched (a few KB through the proxy). System
images pulled during the first configured boot before injection (kubelet,
~100-200 MiB) may re-download once per node; all CRI workload images come
from the seed. New stacks (Rook/Ceph, metrics-server) are downloaded once
through the proxy and can later be served with the official
`talosctl image cache-create/cache-serve` tooling.

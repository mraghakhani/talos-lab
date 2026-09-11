# TODO.md

Prioritized roadmap for `talos-lab`.

Legend:
- `[x]` complete
- `[ ]` pending
- `P0` blocks reliable operation
- `P1` next milestone
- `P2` hardening / convenience
- `P3` future improvement

## Completed foundation

- [x] QEMU/KVM/libvirt selected as virtualization stack
- [x] Dedicated libvirt network `192.168.231.0/24`
- [x] Dedicated libvirt storage pool
- [x] Six-node Talos VM topology
- [x] Stable node MAC/IP mapping
- [x] Talos `v1.14.0`
- [x] Kubernetes `v1.37.0`
- [x] Three-control-plane etcd cluster
- [x] Talos node traffic through host HTTP proxy
- [x] Talos image pre-pull task with retries
- [x] Cilium `1.20.1`
- [x] kube-proxy replacement
- [x] Hubble enabled
- [x] Cilium test-image pre-pull
- [x] Cilium core connectivity suite passing
- [x] Scoped Pod Security exemption for Cilium connectivity tests
- [x] `vm:stop:force`
- [x] Repository lint / secret-scan workflow
- [x] Argo CD bootstrap moved to separate `talos-gitops` repository

## P0 — foundation correctness

- [ ] Audit `task talos:bootstrap` marker/state logic
  - Marker must only represent a genuinely initialized etcd cluster
  - Verify etcd service is `Running`
  - Verify bootstrap node appears in etcd membership
  - Avoid false "completed" state after failed image pull
- [ ] Add a single `task foundation:status`
  - libvirt network
  - storage pool
  - VM power state
  - Talos mTLS reachability
  - etcd membership
  - Kubernetes nodes
  - Cilium status
- [ ] Add `task vm:shutdown` for graceful shutdown
  - Prefer Talos shutdown first
  - Fall back to libvirt only when explicitly requested
  - Keep `vm:stop:force` separate
- [ ] Verify a cold restart of the entire lab
  - power off all VMs
  - start them
  - etcd recovers
  - API VIP recovers
  - Kubernetes nodes Ready
  - Cilium healthy
- [ ] Verify full rebuild from a clean host-side state using only tracked configuration + ignored local secrets

## P1 — reproducibility / disaster recovery

- [ ] Add `docs/REBUILD.md`
  - fresh host
  - required packages
  - network
  - storage
  - Talos ISO
  - VMs
  - configs
  - bootstrap
  - Cilium
- [ ] Add configuration drift check
  - compare desired VM definitions with libvirt
  - compare desired Talos config hash with applied config where possible
- [ ] Add backup/export task for critical local-only state
  - Talos secrets bundle
  - talosconfig
  - kubeconfig
  - any host-side CA material
  - document restore procedure
- [ ] Add libvirt XML snapshot/export task for auditability
- [ ] Add `task diagnose:bundle`
  - VM status
  - Talos service status
  - etcd members
  - Kubernetes nodes/events
  - Cilium status
  - no secret values in bundle

## P2 — host hardening / operator UX

- [ ] Remove repeated polkit password prompts for approved libvirt management
  - document least-privilege group/polkit option
  - do not broadly grant passwordless root
- [ ] Make preflight explicitly verify `kvm_intel`/KVM acceleration state without false warnings
- [ ] Add disk-space thresholds for libvirt pool
- [ ] Add proxy reachability checks for:
  - registry.k8s.io
  - quay.io
  - GitHub releases
  - Helm repositories used during bootstrap
- [ ] Add bounded retries/timeouts to all remote downloads
- [ ] Add structured log directory for failed operations
- [ ] Add `task help` / categorized Taskfile summaries if not already present

## P2 — upgrade practice

- [ ] Document Talos upgrade procedure
- [ ] Document Kubernetes upgrade procedure
- [ ] Document Cilium upgrade procedure
- [ ] Practice rolling control-plane upgrades
- [ ] Practice rolling worker upgrades
- [ ] Add version compatibility notes before future bumps
- [ ] Never upgrade all control planes simultaneously

## P3 — chaos / recovery drills

- [ ] Kill one control-plane VM and verify etcd/API availability
- [ ] Kill one worker and verify workload rescheduling
- [ ] Temporarily stop host proxy and document failure modes
- [ ] Corrupt/remove one VM definition while preserving disk and practice recovery
- [ ] Test worker data-disk replacement
- [ ] Test etcd backup/restore in a disposable clone of the lab

## Definition of done for this repo

The infrastructure foundation is considered mature when:
- a new machine can reproduce it from tracked configuration,
- cold restart is reliable,
- one-node failures are recoverable,
- upgrades are documented and tested,
- no day-2 platform app depends on manual commands in this repo,
- `task repo:check` and core foundation health checks are green.

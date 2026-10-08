# Talos Dev Cluster --- Next Steps Roadmap

A practical checklist for turning a working Talos + Kubernetes + Argo CD
lab into a reliable platform for backend development and Kubernetes
practice.

> **Current baseline:** Talos cluster is running and Argo CD is
> installed. Confirm actual node/network details before applying
> examples; this roadmap does not assume every component is already
> configured.

## Goals

-   Keep the cluster reproducible and recoverable.
-   Manage infrastructure and applications declaratively through Git +
    Argo CD.
-   Establish networking, ingress, storage, security, and observability
    in a deliberate order.
-   Deploy a real backend workload and practice production-style
    operations.

## Phase 0 --- Capture a known-good baseline

-   [x] Confirm Talos and Kubernetes health.
-   [x] Confirm all nodes are `Ready`.
-   [x] Confirm core system pods are healthy.
-   [x] Confirm Argo CD is reachable and can sync a test application.
-   [x] Save the current Talos configuration and document how the
    cluster is created.
-   [x] Record versions: Talos, Kubernetes, Argo CD, CNI, and Helm
    charts.
-   [x] Take an etcd snapshot and verify where it is stored.
-   [x] Keep proxy settings and image-pull requirements documented; test
    that a newly created node can reach required registries.

Useful checks:

``` bash
talosctl health
talosctl version
talosctl etcd status
talosctl etcd members

kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
kubectl get applications -n argocd
```

**Exit criteria:** all nodes are `Ready`, system pods are healthy, Argo
CD is syncing, and recovery/configuration notes exist.

## Phase 1 --- Put the lab configuration in Git

Create a repository before adding many more components. Store manifests,
Helm values, app definitions, and documentation there.

Suggested layout:

``` text
talos-lab/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── operations.md
│   └── troubleshooting.md
├── clusters/
│   └── dev/
│       ├── root-app.yaml
│       └── infrastructure/
├── apps/
│   ├── whoami/
│   └── demo-api/
└── secrets/
    └── README.md
```

-   [x] Commit the current Argo CD configuration and app manifests.
-   [x] Decide whether this repo uses plain YAML, Helm, Kustomize, or a
    mix.
-   [x] Create a root Argo CD Application (app-of-apps) or an
    ApplicationSet only if it adds value.
-   [x] Configure automated sync cautiously: start with pruning disabled
    until you understand the deletion implications.
-   [x] Never commit kubeconfig, Talos client credentials, private keys,
    tokens, or plaintext application secrets.
-   [x] Add a README with bootstrap steps and required environment
    variables.

**Exit criteria:** you can rebuild the app configuration from Git rather
than terminal history.

## Phase 2 --- Verify networking and choose the CNI

First inspect the current CNI; do not install a second CNI over an
existing one.

``` bash
kubectl get pods -n kube-system -o wide
kubectl get daemonsets -A
kubectl get nodes -o wide
```

-   [x] Identify the CNI installed by the cluster creation flow.
-   [x] Verify pod-to-pod, pod-to-Service, and DNS connectivity.
-   [x] Decide whether to keep the current CNI or rebuild the lab
    specifically for Cilium.
-   [x] If adopting Cilium, plan its Talos-specific installation and
    kube-proxy replacement settings before changing anything.
-   [x] Enable Hubble only after basic connectivity is stable.
-   [x] Test a NetworkPolicy with a small disposable workload.

**Recommendation:** if Cilium is a learning goal, a clean, reproducible
cluster configured for Cilium from the beginning is safer than layering
it over an unknown existing CNI.

**Exit criteria:** documented CNI, working cluster DNS, working Service
routing, and a repeatable network-policy test.

## Phase 3 --- Expose applications to your LAN

Pick one ingress approach and keep the first version simple.

Options include: - **Gateway API with Cilium**, if Cilium is the chosen
CNI and Gateway API is a learning goal. - A Gateway API implementation
that fits the CNI and lab requirements. - An Ingress controller if
compatibility with existing applications matters more than learning
Gateway API.

-   [x] Decide how LAN clients will reach the cluster.
-   [x] Decide whether a `LoadBalancer` implementation is required for
    the chosen network.
-   [x] For a local QEMU network, verify which addresses are reachable
    from the host and LAN before selecting an IP pool.
-   [x] Deploy a tiny test app and expose it with an HTTP route.
-   [ ] Test DNS, routing, and access from both the host and another LAN
    device if needed.
-   [ ] Document firewall rules and address reservations.

**Important:** do not assume an IP pool such as `10.5.0.100-150` is safe
just because the nodes use `10.5.0.0/24`. Confirm the actual QEMU
network, DHCP range, and routing first. L2 announcements also require a
network topology where those announcements can reach clients.

**Exit criteria:** a test application is reachable at a stable
address/name from the intended clients.

## Phase 4 --- Add storage only when a workload needs it

Start with the smallest storage option that meets the lab's needs.
Local-path storage is simple but usually ties data to a particular node;
it is not highly available.

-   [ ] Decide which workloads need persistence.
-   [ ] Install a suitable StorageClass/provisioner.
-   [ ] Create a PVC and test writing data.
-   [ ] Delete/recreate the pod and verify the data survives.
-   [ ] Document node-loss behavior and backup/restore steps.
-   [ ] Defer distributed storage such as Rook/Ceph until you
    specifically want to learn its operational model and have suitable
    disks/resources.

**Exit criteria:** a documented PVC lifecycle test and a clear
understanding of what happens if a node or VM is lost.

## Phase 5 --- TLS and secrets

-   [ ] Install cert-manager if certificate automation is needed.
-   [ ] Start with a local development CA or another appropriate lab
    issuer.
-   [ ] Issue a certificate and verify HTTPS end-to-end through the
    chosen Gateway/Ingress.
-   [ ] Choose a secret-management approach before storing more
    credentials in Git.
-   [ ] For GitOps, consider SOPS with age or an external secret
    manager; understand key backup and recovery.
-   [ ] Rotate any credentials that were accidentally committed or
    exposed.

**Exit criteria:** HTTPS works for a test app and secrets are not stored
in plaintext in the repository.

## Phase 6 --- Observability

Build up incrementally instead of installing a huge stack at once.

1.  [ ] Install Metrics Server if it is not already present.
2.  [ ] Verify `kubectl top nodes` and `kubectl top pods -A`.
3.  [ ] Add Prometheus and Grafana for metrics.
4.  [ ] Add a log collection pipeline (for example, Loki plus an agent)
    if centralized logs are useful.
5.  [ ] Add OpenTelemetry to the demo service when ready.
6.  [ ] Create a few actionable alerts: node unavailable, pod
    crash-looping, PVC nearly full, and application error rate elevated.

Useful checks:

``` bash
kubectl top nodes
kubectl top pods -A
kubectl get events -A --sort-by=.lastTimestamp
```

**Exit criteria:** you can answer "is it healthy?", "what changed?", and
"where is the error?" without manually inspecting every pod.

## Phase 7 --- Deploy a real backend workload

Use a small service in a language you work with (for example, .NET or
Go), plus only the dependencies needed for the exercise.

-   [ ] Build the image and make sure the cluster can pull it through
    the configured network/proxy.
-   [ ] Deploy via Argo CD, not a one-off `kubectl apply`.
-   [ ] Set resource requests/limits.
-   [ ] Add startup, readiness, and liveness probes with appropriate
    semantics.
-   [ ] Add a Service and expose it through the chosen Gateway/Ingress.
-   [ ] Configure app settings separately from secrets.
-   [ ] Add PostgreSQL and/or Redis only if the application needs them;
    use persistent storage and backups for stateful data.
-   [ ] Add graceful shutdown and test rolling updates.
-   [ ] Add a PodDisruptionBudget only where it makes sense; it does not
    protect against every failure.
-   [ ] Add NetworkPolicies and verify both allowed and denied traffic.
-   [ ] Test failure scenarios: kill a pod, make a dependency
    unavailable, and deploy a bad version then roll back.

**Exit criteria:** a service deploys from Git, serves traffic, emits
useful telemetry, and survives routine pod replacement.

## Phase 8 --- Operations and recovery drills

-   [ ] Document how to create and destroy the QEMU lab.
-   [ ] Document how to restore kubeconfig and Talos client
    configuration safely.
-   [ ] Take an etcd snapshot and store it outside the control-plane VM.
-   [ ] Practice restoring/recreating a disposable cluster before
    relying on backups.
-   [ ] Document Talos OS upgrades separately from Kubernetes upgrades.
-   [ ] Test one worker reboot and verify workloads recover.
-   [ ] Track image versions and chart versions; avoid floating tags for
    reproducibility.
-   [ ] Keep a short troubleshooting runbook for DNS, image pulls, CNI,
    storage, and Argo CD sync failures.

Useful commands:

``` bash
talosctl health
talosctl services
talosctl dmesg -f
talosctl logs kubelet -f
talosctl etcd snapshot ./etcd-$(date +%F).snapshot

kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
```

## Recommended order at a glance

  ------------------------------------------------------------------------
                         Order Deliverable           Why it comes here
  ---------------------------- --------------------- ---------------------
                             1 Baseline health +     Avoid building on a
                               documentation         broken foundation

                             2 GitOps repo + Argo CD Make every next step
                               root app              reproducible

                             3 Confirm CNI and       Networking is
                               cluster DNS           foundational

                             4 Gateway/Ingress +     Makes apps usable
                               stable access         

                             5 Basic persistent      Enables stateful apps
                               storage               

                             6 TLS + secret          Avoids insecure app
                               management            configuration

                             7 Metrics, logs, alerts Makes failures
                                                     diagnosable

                             8 Backend +             Validates the
                               dependencies          platform end to end

                             9 Recovery and upgrade  Turns a demo into an
                               drills                operationally useful
                                                     lab
  ------------------------------------------------------------------------

## First session: do these next

-   [x] Run the Phase 0 checks and save the output in `docs/`.
-   [x] Inspect `kubectl get pods -n kube-system -o wide` to identify
    the CNI.
-   [x] Create the Git repository structure.
-   [x] Add the existing Argo CD app configuration to Git.
-   [x] Deploy one tiny test app through Argo CD.
-   [x] Only then decide whether to adopt Cilium and Gateway API or keep
    the current networking stack.

## Decisions to record

Fill these in as you make them:

-   **CNI:** TODO
-   **Ingress/Gateway implementation:** TODO
-   **LAN access / LoadBalancer strategy:** TODO
-   **Storage provisioner:** TODO
-   **Certificate issuer:** TODO
-   **Secret management:** TODO
-   **Metrics/logging stack:** TODO
-   **Application workload:** TODO
-   **Backup destination:** TODO

------------------------------------------------------------------------

Keep the lab boring at the foundation and interesting at the workload
layer. Add one platform capability at a time, prove it works, and commit
the working state before moving on.

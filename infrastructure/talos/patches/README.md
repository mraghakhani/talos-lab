# Talos configuration patches

These files are committed **intent**, not generated machine configurations.

Talos 1.14 generates Kubernetes configuration as dedicated multi-document resources. To avoid strict-validation conflicts, this lab does not mix the deprecated v1alpha1 fields with their 1.14 replacements:

- `common.yaml.tmpl` configures `KubeNetworkConfig`, `KubeNodeConfig.nodeIP`, and the host HTTP proxy using `EnvironmentConfig`.
- `controlplane.yaml.tmpl` adds the lab role label, disables kube-proxy with `KubeProxyConfig`, and deletes the generated `KubeFlannelCNIConfig` so Cilium can own CNI.
- `worker.yaml.tmpl` adds the lab role label through `KubeNodeConfig`.
- Per-node networking is generated from `config/nodes.yaml` into `state/rendered/talos/nodes/`. Each node receives a stable link alias selected by its permanent MAC, explicit DHCPv4, a static hostname (`auto: off`), and control-plane nodes receive the Layer-2 Kubernetes API VIP.

`infrastructure/talos/generated/` contains cluster secrets, talosconfig, kubeconfig, and fully rendered machine configs. It is gitignored and must be treated as sensitive.

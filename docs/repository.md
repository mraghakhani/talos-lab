# Repository model

## Desired remote layout

The workstation repository is the authoring copy. GitHub is the durable external remote; the future local Gitea instance is the in-lab GitOps remote used by Argo CD.

```text
workstation
  ├── github  -> durable external copy / CI / collaboration
  └── gitea   -> local platform source consumed by Argo CD
```

Do not make Kubernetes depend on GitHub availability. Once Gitea exists, Argo CD should pull from Gitea. GitHub remains a backup/collaboration remote and can mirror to/from Gitea according to the workflow we choose later.

## State rules

Committed:

- desired infrastructure configuration
- version pins
- templates and patches
- Kubernetes/Argo manifests
- scripts and Taskfiles
- encrypted SOPS documents when intentionally created

Never committed:

- Talos machine secrets or generated machine configs
- `talosconfig` / kubeconfig files
- OpenBao data, recovery material, root tokens, or unseal/recovery secrets
- private `age` identities
- private TLS/signing keys
- generated libvirt state, downloaded ISOs, or caches

`task repo:check` enforces the most important parts locally and in GitHub Actions.

## Branch protection

After the `validate` workflow has completed successfully once, protect the default branch in GitHub and require the `repo` validation job before merge. Do the same in Gitea after it is deployed.

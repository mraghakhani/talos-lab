# Security policy for this lab repository

This repository intentionally contains infrastructure definitions but must not contain live credentials or private keys.

If a secret is committed accidentally, deleting the file in a later commit is not sufficient: rotate/revoke the credential and purge it from Git history as appropriate.

Before pushing changes, run:

```bash
task repo:check
```

Sensitive runtime material belongs in ignored local state during bootstrap and in OpenBao once the secrets milestone is implemented.

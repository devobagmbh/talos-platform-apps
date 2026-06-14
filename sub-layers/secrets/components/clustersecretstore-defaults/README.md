# Component `secrets/clustersecretstore-defaults`

Boilerplate for `ClusterSecretStore` resources: `vault-local` (in-cluster Vault consumer) and `vault-office-lab-remote` (cross-cluster Vault consumer). Concrete Vault endpoints + auth refs are overridden in the consumer-cluster repo (layer 3).

**Skeleton** — implementation in issue [#15a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets).

**Not in this sub-layer**: Vault Helm release, Vault policies, Vault KV structures, Vault auth-method config — those belong in the consumer repo (layer 3).

## Sync-wave

`10` — needs `secrets/external-secrets` (CRD `ClusterSecretStore`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/clustersecretstore-defaults:vX.Y.Z
```

## Related ADRs

- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)

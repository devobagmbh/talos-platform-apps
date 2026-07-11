# Component `storage-objects/garage-buckets`

`Bucket` CR definitions + access-key generation via ESO/Vault — reconciled by the Garage controller into the S3-bucket namespace.

**Skeleton** — implementation in issue [#13](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects). Default buckets: `tf-state`, `ipxe`, `velero-source-*`, `mimir-blocks`, `loki-chunks`, `tempo-blocks`, `harbor-store`.

## Sync-wave

`10` — needs an active Garage (wave 0) and `secrets/external-secrets` (access-key sync from Vault).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-buckets:vX.Y.Z
```

## Related ADRs

- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)

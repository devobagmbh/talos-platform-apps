# Komponente `storage-objects/garage-buckets`

`Bucket`-CR-Definitionen + Access-Key-Generierung via ESO/Vault — wird vom Garage-Controller in den S3-Bucket-Namespace übernommen.

**Skelett** — Implementation in Issue [#13](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects). Default-Buckets: `tf-state`, `ipxe`, `velero-source-*`, `mimir-blocks`, `loki-chunks`, `tempo-blocks`, `harbor-store`.

## Sync-Wave

`10` — braucht aktiven Garage (Wave 0) und `secrets/external-secrets` (Access-Key-Sync aus Vault).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-buckets:vX.Y.Z
```

## Verwandte ADRs

- ADR-0007 — Platform-Object-Store
- ADR-0011 — Secrets-Management

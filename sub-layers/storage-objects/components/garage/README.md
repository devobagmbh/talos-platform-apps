# Component `storage-objects/garage`

Garage (Helm `deuxfleurs/garage` or custom chart) — S3-compatible object store, ZFS block storage via Linstor. Replication factor + compaction schedule ship as defaults; cluster-specific values (listener VIP, topology) live in the consumer repo.

**Skeleton** — implementation in issue [#13](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects).

## Sync-wave

`0` — ships the StatefulSet and the S3 endpoint that all bucket consumers need.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage:vX.Y.Z
```

## Consumed by

- A single-node consumer — single-node cluster
- A multi-node consumer — 3-node cluster
- **DS720+** — a separate cluster, tier-2 backup target (NOT a member of the K8s cluster)

## Related ADRs

- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)

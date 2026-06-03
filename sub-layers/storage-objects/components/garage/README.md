# Komponente `storage-objects/garage`

Garage (Helm `deuxfleurs/garage` oder custom-chart) — S3-kompatibler Object-Store, ZFS-Block-Storage via Linstor. Replication-Faktor + Compaction-Schedule kommen als Defaults; Cluster-spezifische Werte (Listener-VIP, Topology) im Konsumenten-Repo.

**Skelett** — Implementation in Issue [#13](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects).

## Sync-Wave

`0` — bringt den StatefulSet und den S3-Endpoint, den alle Bucket-Konsumenten brauchen.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage:vX.Y.Z
```

## Konsumiert von

- **Seeder** — Single-Node-Cluster
- **Office-Lab** — 3-Node-Cluster
- **DS720+** — separates Cluster, Tier-2-Backup-Ziel (KEIN Mitglied des K8s-Clusters)

## Verwandte ADRs

- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)

# Komponente `databases/cnpg`

CloudNativePG-Operator (Helm `cnpg/cloudnative-pg`) — bringt `postgresql.cnpg.io/Cluster`-CRD und zugehörige Operator-Pods plus Devoba-Defaults (PodMonitor-Pattern, BackupConfig-Skelett, StorageClass-Mapping auf Piraeus/LINSTOR).

**Skelett** — Implementation in Issue [#15](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+databases).

Hinweis: Konkrete `Cluster`-CRs (für Dex, Harbor, PowerDNS …) gehören in den jeweiligen App-Sub-Layer/-Cluster-Repo, **nicht** hier.

## Sync-Wave

`0` — bringt die CRDs, die alle konsumierenden Apps brauchen.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/databases/cnpg:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)

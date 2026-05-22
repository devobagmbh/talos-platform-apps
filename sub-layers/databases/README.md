# Sub-Layer `databases`

CloudNativePG (CNPG) als Postgres-Operator für die Devoba-Plattform.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| CNPG-Operator | Helm `cnpg/cloudnative-pg` | Operator + CRDs für Postgres-Cluster |
| CNPG-Defaults | dieses Repo | Standard-PodMonitor, BackupConfig, StorageClass-Mapping (Linstor) |

## Konsumiert von

- **Seeder** — kein Postgres-Konsument vorgesehen
- **DHQ** — Konsumenten sind Dex, Harbor, PowerDNS, ggf. Workload-Apps. Jeder Konsument deployt sein eigenes `Cluster`-CR im eigenen Sub-Layer / Argo-App.

## Inhalt

- `helm/values.yaml` — Operator-Defaults (Resource-Requests, MonitoringEnabled, etc.)
- `manifests/storage-class-linstor.yaml` — StorageClass-Mapping auf Piraeus/LINSTOR (oder Verweis falls im Cluster-Repo)
- `manifests/backup-base-policy.yaml` — gemeinsame Backup-Defaults (Garage als WAL/Snapshot-Ziel)

Hinweis: Postgres-`Cluster`-CRs gehören in den jeweiligen App-Sub-Layer (z. B. `secrets/` für Dex-DB, `dns/` für PowerDNS-DB, `registry/` für Harbor-DB), nicht hier.

## Backlog-Issue

[#15 — Sub-Layer `databases/`: CNPG](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+databases)

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

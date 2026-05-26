# Sub-Layer `databases`

CloudNativePG (CNPG) als Postgres-Operator für die Devoba-Plattform.

OCI-Distribution pro Komponente (ADR-0009). Konkrete `Cluster`-CRs (Dex, Harbor, PowerDNS …) bleiben in den jeweiligen App-Sub-Layern bzw. im Konsumenten-Cluster-Repo.

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`cnpg`](components/cnpg/) | 0 | Helm `cnpg/cloudnative-pg` + Devoba-Defaults | `oci://.../databases/cnpg:vX.Y.Z` |

## Konsumiert von

- **Seeder** — kein Postgres-Konsument vorgesehen
- **DHQ** — Konsumenten sind Dex, Harbor, PowerDNS, ggf. Workload-Apps

## Backlog-Issue

[#15 — Sub-Layer `databases/`: CNPG](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+databases)

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

# Sub-Layer `databases`

Daten-Operatoren der Devoba-Plattform: **CloudNativePG (CNPG)** für PostgreSQL und **hyperspike/valkey-operator** für Valkey (Redis-wire-kompatibel, Capability `redis-managed`).

OCI-Distribution pro Komponente (ADR-0009). Konkrete `Cluster`-/`Valkey`-CRs (Dex, Harbor, PowerDNS …) bleiben in den jeweiligen App-Sub-Layern bzw. im Konsumenten-Cluster-Repo.

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`cnpg`](components/cnpg/) | 0 | Helm `cnpg/cloudnative-pg` + Devoba-Defaults | `oci://.../databases/cnpg:vX.Y.Z` |
| [`valkey-operator`](components/valkey-operator/) | 0 | vendored `install.yaml` (hyperspike/valkey-operator v0.0.61) | `oci://.../databases/valkey-operator:vX.Y.Z` |

## Konsumiert von

- Ein Cache-only-Konsument — Harbor-Cache via `valkey-operator` (`redis-managed`), ohne Postgres-Konsumenten (Harbor/crossview-Postgres erst beim Wiring #40/#39).
- Ein Full-Database-Konsument — Postgres-Konsumenten sind Dex, Harbor, PowerDNS, ggf. Workload-Apps; Valkey für Cache-Bedarf.

## Backlog-Issue

[#15 — Sub-Layer `databases/`: CNPG](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+databases)

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

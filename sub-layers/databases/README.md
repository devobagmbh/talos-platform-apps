# Sub-layer `databases`

Data operators of the Devoba platform: **CloudNativePG (CNPG)** for PostgreSQL and **hyperspike/valkey-operator** for Valkey (Redis-wire-compatible, capability `redis-managed`).

OCI distribution per component (ADR-0009). Concrete `Cluster`/`Valkey` CRs (Dex, Harbor, PowerDNS …) stay in the respective app sub-layers or in the consumer-cluster repo.

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`cnpg`](components/cnpg/) | 0 | Helm `cnpg/cloudnative-pg` + Devoba defaults | `oci://.../databases/cnpg:vX.Y.Z` |
| [`valkey-operator`](components/valkey-operator/) | 0 | vendored `install.yaml` (hyperspike/valkey-operator v0.0.61) | `oci://.../databases/valkey-operator:vX.Y.Z` |

## Consumed by

- A cache-only consumer — Harbor cache via `valkey-operator` (`redis-managed`), without Postgres consumers (Harbor/crossview Postgres only at wiring #40/#39).
- A full-database consumer — Postgres consumers are Dex, Harbor, PowerDNS, and possibly workload apps; Valkey for caching needs.

## Backlog issue

[#15 — Sub-layer `databases/`: CNPG](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+databases)

## Related ADRs

- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

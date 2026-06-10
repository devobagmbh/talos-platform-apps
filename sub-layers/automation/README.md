# Sub-Layer `automation`

Velero (Cluster-Backup). Dependency-Update-Automation läuft über **GitHub Dependabot** (nativ, `.github/dependabot.yml`) — kein self-hosted Renovate im Katalog (Entscheidung 2026-06-10).

OCI-Distribution pro Komponente (ADR-0009).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`velero`](components/velero/) | 0 | Helm `vmware-tanzu/velero` mit Restic | `oci://.../automation/velero:vX.Y.Z` |

## Konsumiert von

- **Seeder** — `velero`
- **Office-Lab** — `velero`

## Backlog-Issue

[#16 — Sub-Layer `automation/`: Renovate + Velero](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation)

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy (Tier-2 via DS720+/Garage)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

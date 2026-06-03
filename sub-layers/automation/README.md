# Sub-Layer `automation`

Renovate (Dependency-Updates) und Velero (Cluster-Backup).

OCI-Distribution pro Komponente (ADR-0009).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`renovate`](components/renovate/) | 0 | Helm `renovatebot/renovate` | `oci://.../automation/renovate:vX.Y.Z` |
| [`velero`](components/velero/) | 0 | Helm `vmware-tanzu/velero` mit Restic | `oci://.../automation/velero:vX.Y.Z` |

Beide parallel — keine Inter-Komponenten-Abhängigkeit.

## Konsumiert von

- **Seeder** — nur `velero`
- **Office-Lab** — beide

## Backlog-Issue

[#16 — Sub-Layer `automation/`: Renovate + Velero](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation)

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy (Tier-2 via DS720+/Garage)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

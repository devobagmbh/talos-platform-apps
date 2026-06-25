# Sub-layer `automation`

Velero (cluster backup). Dependency-update automation runs through **GitHub Dependabot** (native, `.github/dependabot.yml`) — no self-hosted Renovate in the catalog (decision 2026-06-10).

OCI distribution per component (ADR-0009).

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`velero-crds`](components/velero-crds/) | -1 | Velero CRDs (strict-B, ADR-0028) | `oci://.../automation/velero-crds:vX.Y.Z` |
| [`velero`](components/velero/) | 0 | Helm `vmware-tanzu/velero` with Restic | `oci://.../automation/velero:vX.Y.Z` |

## Consumed by

- Any consumer cluster that needs backups — `velero`

## Backlog issue

[#16 — Sub-layer `automation/`: Renovate + Velero](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation)

## Related ADRs

- [ADR-0008 — Backup-Strategy (tier-2 via DS720+/Garage)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

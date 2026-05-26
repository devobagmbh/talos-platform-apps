# Komponente `automation/velero`

Velero (Helm `vmware-tanzu/velero`) mit Restic — Backup von K8s-Ressourcen und PVCs nach DS720+-Garage (S3).

**Skelett** — Implementation in Issue [#16](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation).

## Sync-Wave

`0` — kein Inter-Komponenten-Dependency.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/velero:vX.Y.Z
```

## Konsumiert von

- **Seeder** — Backups von tf-state, ArgoCD-Config, Harbor
- **DHQ** — Vollbackup

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy (Tier-2 via DS720+/Garage)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)

# Component `automation/velero`

Velero (Helm `vmware-tanzu/velero`) with Restic — backup of K8s resources and PVCs to the Garage S3 object store.

**Skeleton** — implementation in issue [#16](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation).

## Sync-wave

`0` — no inter-component dependency.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/velero:vX.Y.Z
```

## Consumed by

- A bootstrap / control-plane consumer — backups of tf-state, ArgoCD config, Harbor
- A workload consumer — full backup

## Related ADRs

- [ADR-0008 — Backup-Strategy (tier-2 via Garage)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)

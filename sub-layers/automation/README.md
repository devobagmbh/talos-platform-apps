# Sub-Layer `automation`

Renovate (Dependency-Updates) und Velero (Cluster-Backup) als OCI-Sub-Layer.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| Renovate | self-hosted, Helm `renovatebot/renovate` | scannt `talos-*-cluster` und `talos-platform-apps` auf neue Upstream-Tags und öffnet PRs |
| Velero | Helm `vmware-tanzu/velero` mit Restic | Backup von K8s-Ressourcen und PVCs nach DS720+-Garage (S3) |

## Konsumiert von

- **Seeder** — nur Velero (Backups von tf-state, ArgoCD-Config, Harbor)
- **DHQ** — Renovate (überwacht die Devoba-Plattform-Repos) und Velero

## Inhalt

- `helm/` — Werte-Files je Komponente (Defaults, cluster-spezifisches in den Konsumenten-Repos)
- `manifests/` — ggf. zusätzliche `Schedule`-/`ConfigMap`-/`Policy`-Resources (Velero-Backup-Schedules, Renovate-Config-Presets)
- `rendered/` — Output von `helm template`, gitignored, wird in CI gerendert und per `oras push` als OCI publiziert

## Backlog-Issue

[#16 — Sub-Layer `automation/`: Renovate + Velero](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation)

## Verwandte ADRs

- [ADR-0008 — Backup-Strategy (Tier-2 via DS720+/Garage)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

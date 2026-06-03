# Komponente `automation/renovate`

Self-hosted Renovate (Helm `renovatebot/renovate`) — scannt `talos-*-cluster` und `talos-platform-apps` auf neue Upstream-Tags und öffnet PRs.

**Skelett** — Implementation in Issue [#16](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+automation).

## Sync-Wave

`0` — kein Inter-Komponenten-Dependency.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/renovate:vX.Y.Z
```

## Konsumiert von

- **Office-Lab** — überwacht die Devoba-Plattform-Repos
- **Seeder** — nein

## Verwandte ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

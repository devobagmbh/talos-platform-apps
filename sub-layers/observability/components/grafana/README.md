# Component `observability/grafana`

Helm `grafana/grafana` — dashboards + alerts UI. Datasources on Loki/Mimir/Tempo, OIDC via Dex.

**Skeleton** — implementation in issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-wave

`20` — needs datasource endpoints from wave 10.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/grafana:vX.Y.Z
```

## Consumed by

- A full-stack consumer — full stack
- A forwarder-only consumer — no (Grafana is consolidated on the full-stack consumer)

## Related ADRs

- ADR-0015 — Monitoring architecture
- ADR-0010 — Identity-Provider

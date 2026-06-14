# Komponente `observability/grafana`

Helm `grafana/grafana` — Dashboards + Alerts-UI. Datasources auf Loki/Mimir/Tempo, OIDC via Dex.

**Skelett** — Implementation in Issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-Wave

`20` — braucht Datasource-Endpoints aus Wave 10.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/grafana:vX.Y.Z
```

## Konsumiert von

- Ein Full-Stack-Konsument — Vollstack
- Ein Forwarder-only-Konsument — nein (Grafana wird auf dem Full-Stack-Konsumenten konsolidiert)

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0010 — Identity-Provider](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)

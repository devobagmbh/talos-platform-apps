# Komponente `monitoring/alloy`

Helm `grafana/alloy` — DaemonSet als unified Telemetry-Collector (ersetzt Promtail). Sources: kubernetes-pods, journald, otelhttp. Sinks: Loki (Logs), Mimir (Metrics), Tempo (Traces).

**Skelett** — Implementation in Issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-Wave

`20` — braucht die drei Storage-Komponenten (Wave 10) als Endpoints. Auf Seeder als reiner Forwarder konfiguriert (Sinks → Office-Lab-Endpoints).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/monitoring/alloy:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

# Komponente `monitoring/kube-prometheus-stack`

Helm `prometheus-community/kube-prometheus-stack` mit **Prometheus disabled** (Mimir ersetzt es). Liefert ausschließlich Operator + CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `AlertmanagerConfig`) und den Alertmanager.

**Skelett** — Implementation in Issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-Wave

`0` — bringt die CRDs, die alle anderen Monitoring-Komponenten als ServiceMonitor-/PrometheusRule-Quellen nutzen.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/monitoring/kube-prometheus-stack:vX.Y.Z
```

## Konsumiert von

- **Office-Lab** — Vollstack (Alertmanager lokal)
- **Seeder** — Subset: nur Operator + Alertmanager-Watchdog

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

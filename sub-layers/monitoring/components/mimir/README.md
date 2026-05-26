# Komponente `monitoring/mimir`

Helm `grafana/mimir-distributed` — Metric-Storage, Garage-S3-Backend (`mimir-blocks`-Bucket). Ersetzt Cluster-lokales Prometheus.

**Skelett** — Implementation in Issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-Wave

`10` — braucht Garage-Bucket aus `storage-objects/garage-buckets`.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/monitoring/mimir:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

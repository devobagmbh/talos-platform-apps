# Komponente `observability/loki`

Helm `grafana/loki` (distributed-Mode) — Log-Aggregation, Garage-S3-Backend (`loki-chunks` und `loki-ruler`-Buckets).

**Skelett** — Implementation in Issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-Wave

`10` — braucht Garage-Bucket aus `storage-objects/garage-buckets`.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/loki:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)

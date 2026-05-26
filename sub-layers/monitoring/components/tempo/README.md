# Komponente `monitoring/tempo`

Helm `grafana/tempo-distributed` — Trace-Storage, Garage-S3-Backend (`tempo-blocks`-Bucket).

**Skelett** — Implementation in Issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-Wave

`10` — braucht Garage-Bucket aus `storage-objects/garage-buckets`.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/monitoring/tempo:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0015 — Monitoring-Architektur](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

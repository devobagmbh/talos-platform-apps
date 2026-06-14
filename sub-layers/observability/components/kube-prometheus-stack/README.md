# Component `observability/kube-prometheus-stack`

Helm `prometheus-community/kube-prometheus-stack` with **Prometheus disabled** (Mimir replaces it). Ships only the operator + CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `AlertmanagerConfig`) and the Alertmanager.

**Skeleton** — implementation in issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-wave

`0` — ships the CRDs that all other monitoring components use as ServiceMonitor / PrometheusRule sources.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/kube-prometheus-stack:vX.Y.Z
```

## Consumed by

- A full-stack consumer — full stack (Alertmanager local)
- A forwarder-only consumer — subset: operator + Alertmanager watchdog only

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

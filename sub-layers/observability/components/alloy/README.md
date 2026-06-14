# Component `observability/alloy`

Helm `grafana/alloy` — DaemonSet as a unified telemetry collector (replaces Promtail). Sources: kubernetes-pods, journald, otelhttp. Sinks: Loki (logs), Mimir (metrics), Tempo (traces).

**Skeleton** — implementation in issue [#17](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring).

## Sync-wave

`20` — needs the three storage components (wave 10) as endpoints. On a forwarder-only consumer, configured as a pure forwarder (sinks → the full-stack consumer's endpoints).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/alloy:vX.Y.Z
```

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

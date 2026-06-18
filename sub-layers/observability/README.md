# Sub-layer `observability`

LGTM-A stack (Loki + Grafana + Tempo + Mimir + Alloy) + kube-prometheus-stack (operator-only) + Hubble (Cilium network-flow visibility).

OCI distribution per component (ADR-0009). Consumer clusters pick the subset (a forwarder-only consumer = operator + Alloy forwarder, a full-stack consumer = full stack).

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`prometheus-operator-crds`](components/prometheus-operator-crds/) | -1 | Helm `prometheus-community/prometheus-operator-crds` (strict-B CRDs artifact, ADR-0028) | `oci://.../observability/prometheus-operator-crds:vX.Y.Z` |
| [`prometheus-operator`](components/prometheus-operator/) | 0 | Helm `prometheus-community/kube-prometheus-stack` (operator-only, strict-B workload artifact, ADR-0028) | `oci://.../observability/prometheus-operator:vX.Y.Z` |
| [`kube-prometheus-stack`](components/kube-prometheus-stack/) | 0 | Helm `prometheus-community/kube-prometheus-stack` (Prometheus disabled) | `oci://.../observability/kube-prometheus-stack:vX.Y.Z` |
| [`loki`](components/loki/) | 10 | Helm `grafana/loki` (distributed) | `oci://.../observability/loki:vX.Y.Z` |
| [`mimir`](components/mimir/) | 10 | Helm `grafana/mimir-distributed` | `oci://.../observability/mimir:vX.Y.Z` |
| [`tempo`](components/tempo/) | 10 | Helm `grafana/tempo-distributed` | `oci://.../observability/tempo:vX.Y.Z` |
| [`alloy`](components/alloy/) | 20 | Helm `grafana/alloy` (DaemonSet) | `oci://.../observability/alloy:vX.Y.Z` |
| [`grafana`](components/grafana/) | 20 | Helm `grafana/grafana`, OIDC via Dex | `oci://.../observability/grafana:vX.Y.Z` |
| [`hubble`](components/hubble/) | 0 | Curated slice of Helm `cilium/cilium` (relay/ui/certs) | `oci://.../observability/hubble:vX.Y.Z` |
| [`metrics-server`](components/metrics-server/) | 0 | Helm `metrics-server` (Resource Metrics API — HPA + `kubectl top`) | `oci://.../observability/metrics-server:vX.Y.Z` |
| [`kube-state-metrics`](components/kube-state-metrics/) | 0 | Helm `prometheus-community/kube-state-metrics` (Kubernetes object-state metrics — `kube_*` series, scraped by Alloy) | `oci://.../observability/kube-state-metrics:vX.Y.Z` |

Wave -1: `prometheus-operator-crds` (strict-B CRDs artifact, ADR-0028 — `monitoring.coreos.com` CRDs land before any controller or consumer CR). Wave 0: operator workload + Hubble + metrics-server + kube-state-metrics. Wave 10: three storage endpoints (all against Garage). Wave 20: collector + UI (need the endpoints from wave 10).

`hubble` is orthogonal to the LGTM-A stack (network-flow visibility from the Cilium substrate, not logs/metrics/traces) and depends only on the Cilium-agent Hubble server — see [`components/hubble/`](components/hubble/) for the substrate precondition.

The bidirectional watchdog AlertmanagerConfig (between two consumer clusters) currently lives as a cross-cluster resource in the consumer repo — once issue #36 is implemented it can become its own `observability/watchdog` component.

## Consumed by

- A full-stack consumer — full stack
- A forwarder-only consumer — subset: `kube-prometheus-stack` + `alloy` (forwarder to the full-stack consumer's endpoints)

## Backlog issue

[#17 — Sub-layer `observability/`: LGTM-A](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring)

Related: [#34 — Full-stack LGTM-A monitoring stack](https://github.com/devobagmbh/talos-platform-apps/issues/34), [#35 — LGTM-A forwarder subset](https://github.com/devobagmbh/talos-platform-apps/issues/35), [#36 — Bidirectional watchdog webhooks](https://github.com/devobagmbh/talos-platform-apps/issues/36).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

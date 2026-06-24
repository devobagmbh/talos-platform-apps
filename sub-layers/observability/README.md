# Sub-layer `observability`

LGTM-A stack (Loki + Grafana + Tempo + Mimir + Alloy) + the Prometheus operator (`prometheus-operator` + `prometheus-operator-crds`) + the Grafana operator (`grafana-operator` + `grafana-operator-crds`) + Hubble (Cilium network-flow visibility).

OCI distribution per component (ADR-0009). Consumer clusters pick the subset (a forwarder-only consumer = operator + Alloy forwarder, a full-stack consumer = full stack).

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`prometheus-operator-crds`](components/prometheus-operator-crds/) | -1 | Helm `prometheus-community/prometheus-operator-crds` (strict-B CRDs artifact, ADR-0028) | `oci://.../observability/prometheus-operator-crds:vX.Y.Z` |
| [`grafana-operator-crds`](components/grafana-operator-crds/) | -1 | Vendored manifests from Helm `grafana/grafana-operator` (strict-B CRDs artifact, ADR-0028 — the `grafana.integreatly.org` CRDs) | `oci://.../observability/grafana-operator-crds:vX.Y.Z` |
| [`prometheus-operator`](components/prometheus-operator/) | 0 | Helm `prometheus-community/kube-prometheus-stack` (operator-only, strict-B workload artifact, ADR-0028) | `oci://.../observability/prometheus-operator:vX.Y.Z` |
| [`grafana-operator`](components/grafana-operator/) | 0 | Helm `grafana/grafana-operator` (operator controller, strict-B workload artifact, ADR-0028) | `oci://.../observability/grafana-operator:vX.Y.Z` |
| [`loki`](components/loki/) | 10 | Helm `grafana/loki` (SingleBinary) | `oci://.../observability/loki:vX.Y.Z` |
| [`mimir`](components/mimir/) | 10 | Helm `grafana/mimir-distributed` | `oci://.../observability/mimir:vX.Y.Z` |
| [`tempo`](components/tempo/) | 10 | Helm `grafana/tempo-distributed` | `oci://.../observability/tempo:vX.Y.Z` |
| [`alloy`](components/alloy/) | 20 | Helm `grafana/alloy` (DaemonSet) | `oci://.../observability/alloy:vX.Y.Z` |
| [`grafana`](components/grafana/) | 20 | Helm `grafana/grafana`, OIDC via Dex | `oci://.../observability/grafana:vX.Y.Z` |
| [`hubble`](components/hubble/) | 0 | Curated slice of Helm `cilium/cilium` (relay/ui/certs) | `oci://.../observability/hubble:vX.Y.Z` |
| [`metrics-server`](components/metrics-server/) | 0 | Helm `metrics-server` (Resource Metrics API — HPA + `kubectl top`) | `oci://.../observability/metrics-server:vX.Y.Z` |
| [`kube-state-metrics`](components/kube-state-metrics/) | 0 | Helm `prometheus-community/kube-state-metrics` (Kubernetes object-state metrics — `kube_*` series, scraped by Alloy) | `oci://.../observability/kube-state-metrics:vX.Y.Z` |
| [`blackbox-exporter`](components/blackbox-exporter/) | 0 | Helm `prometheus-community/prometheus-blackbox-exporter` (synthetic HTTP/TCP/DNS probing — Alloy scrape target + bidirectional cross-cluster watchdog) | `oci://.../observability/blackbox-exporter:vX.Y.Z` |

> **`kube-prometheus-stack` is a stack, not a component** — there is **no**
> `components/kube-prometheus-stack/` directory and **no**
> `oci://…/observability/kube-prometheus-stack` artifact. Every `components/`
> directory must be a release package — `task validate:release-config` gates that
> directory ⇄ package parity, so a stack-shaped skeleton (no package) fails it; that a
> `components/` entry is a *single* component and not a composition is then a
> convention reviewers uphold (the same correctness-vs-completeness split as
> `validate:crd-split`). The stack itself is the *composition* of the components
> above, documented in the dedicated section below.

Wave -1: `prometheus-operator-crds` and `grafana-operator-crds` (strict-B CRDs artifacts, ADR-0028 — the `monitoring.coreos.com` and `grafana.integreatly.org` CRDs land before any controller or consumer CR). Wave 0: operator workload + Hubble + metrics-server + kube-state-metrics. Wave 10: three storage endpoints (all against Garage). Wave 20: collector + UI (need the endpoints from wave 10).

`hubble` is orthogonal to the LGTM-A stack (network-flow visibility from the Cilium substrate, not logs/metrics/traces) and depends only on the Cilium-agent Hubble server — see [`components/hubble/`](components/hubble/) for the substrate precondition.

The bidirectional watchdog AlertmanagerConfig (between two consumer clusters) currently lives as a cross-cluster resource in the consumer repo — once issue #36 is implemented it can become its own `observability/watchdog` component.

## The `kube-prometheus-stack` composition

The upstream `prometheus-community/kube-prometheus-stack` chart bundles operator + CRDs + Prometheus + Alertmanager + node-exporter + kube-state-metrics + Grafana into one release. The catalog **does not** ship that bundle: it splits it into the independently-versioned components above (ADR-0009 granularity; strict-B CRD split per [ADR-0028](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)) so a consumer takes exactly the subset it needs. `kube-prometheus-stack` is therefore a *stack name*, not a distribution unit — it has no component directory and no OCI artifact. Source of truth: [#38](https://github.com/devobagmbh/talos-platform-apps/issues/38).

| Bundled piece | Catalog component | Capability | Issue | Built |
|---|---|---|---|---|
| Operator (controller) | [`prometheus-operator`](components/prometheus-operator/) | api-surface only | [#46](https://github.com/devobagmbh/talos-platform-apps/issues/46) | yes |
| Operator CRDs (strict-B) | [`prometheus-operator-crds`](components/prometheus-operator-crds/) | api-surface only | [#46](https://github.com/devobagmbh/talos-platform-apps/issues/46) | yes |
| Prometheus instance | `prometheus` (consumer-instantiated via the operator `Prometheus` CR) | scrape / store / query — served by `alloy` + `mimir` in this catalog | [#20](https://github.com/devobagmbh/talos-platform-apps/issues/20) | no |
| Alertmanager | `alertmanager` (consumer-instantiated via the operator `Alertmanager` CR) | `alert-routing` | [#43](https://github.com/devobagmbh/talos-platform-apps/issues/43) | no |
| node-exporter | `node-exporter` | — (scrape target) | [#44](https://github.com/devobagmbh/talos-platform-apps/issues/44) | no |
| kube-state-metrics | [`kube-state-metrics`](components/kube-state-metrics/) | — (scrape target) | [#45](https://github.com/devobagmbh/talos-platform-apps/issues/45) | yes |
| Grafana | [`grafana`](components/grafana/) | `dashboards` | [#24](https://github.com/devobagmbh/talos-platform-apps/issues/24) | no |

Long-term metric storage and query are served by [`mimir`](components/mimir/) (`metrics-storage` / `metrics-query`); scraping/forwarding by [`alloy`](components/alloy/) (`metrics-scrape`). The Prometheus and Alertmanager *instances* are consumer concerns wired via the operator CRs, not published catalog artifacts.

## Consumed by

- A full-stack consumer — full stack
- A forwarder-only consumer — subset: `prometheus-operator` + `alloy` (forwarder to the full-stack consumer's endpoints)

## Backlog issue

[#17 — Sub-layer `observability/`: LGTM-A](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+monitoring)

Related: [#34 — Full-stack LGTM-A monitoring stack](https://github.com/devobagmbh/talos-platform-apps/issues/34), [#35 — LGTM-A forwarder subset](https://github.com/devobagmbh/talos-platform-apps/issues/35), [#36 — Bidirectional watchdog webhooks](https://github.com/devobagmbh/talos-platform-apps/issues/36).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

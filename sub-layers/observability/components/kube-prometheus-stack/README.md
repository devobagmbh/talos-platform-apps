# Stack `kube-prometheus-stack` — composition map (NOT a built component)

`kube-prometheus-stack` is a **stack**: the *name of a composition* of individual
observability apps, **not** a catalog component. It is **never built, packaged,
signed, or published** as an OCI artifact — it carries no `helm/`, `manifests/`, or
`customization.yaml`, and the `stack: true` marker in its
[`compatibility.yaml`](compatibility.yaml) excludes it from the Taskfile build/publish
discovery (`COMPONENTS` / `render` / `publish`), so this contract is mechanically
enforced, not merely documented. There is **no**
`oci://…/observability/kube-prometheus-stack` artifact, and there never will be one.

This directory is kept **only as the composition map**: it records which
independently-versioned catalog components together cover what the upstream
`prometheus-community/kube-prometheus-stack` chart bundles into a single release.
A consumer cluster composes the subset it needs from those components directly —
the OCI distribution unit is the **component**, the stack is a grouping, not a
unit ([ADR-0009](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)).

> This README deliberately diverges from the per-component template (no OCI path,
> no sync-wave, no `customization.yaml`): asserting any of those would re-introduce
> the very "kube-prometheus-stack is a shippable component" claim this directory
> exists to retire.

## Composition — the individual components

The upstream chart bundles operator + CRDs + Prometheus + Alertmanager +
node-exporter + kube-state-metrics + Grafana into one release. The catalog splits
that bundle into independently-versioned components (ADR-0009 granularity; strict-B
CRD split per [ADR-0028](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md))
so a consumer takes exactly the subset it needs. Source of truth for the split:
[#38 — `epic(observability)`](https://github.com/devobagmbh/talos-platform-apps/issues/38).

| Bundled piece | Catalog component | Capability | Issue | Built |
|---|---|---|---|---|
| Operator (controller) | [`prometheus-operator`](../prometheus-operator/) | api-surface only | [#46](https://github.com/devobagmbh/talos-platform-apps/issues/46) | ✅ |
| Operator CRDs (strict-B) | [`prometheus-operator-crds`](../prometheus-operator-crds/) | api-surface only | [#46](https://github.com/devobagmbh/talos-platform-apps/issues/46) | ✅ |
| Prometheus instance | `prometheus` (consumer-instantiated via the operator `Prometheus` CR) | `metrics-scrape` / `metrics-storage` / `metrics-query` | [#20](https://github.com/devobagmbh/talos-platform-apps/issues/20) | ⬜ |
| Alertmanager | `alertmanager` (consumer-instantiated via the operator `Alertmanager` CR) | `alert-routing` | [#43](https://github.com/devobagmbh/talos-platform-apps/issues/43) | ⬜ |
| node-exporter | `node-exporter` | metrics source | [#44](https://github.com/devobagmbh/talos-platform-apps/issues/44) | ⬜ |
| kube-state-metrics | [`kube-state-metrics`](../kube-state-metrics/) | metrics source | [#45](https://github.com/devobagmbh/talos-platform-apps/issues/45) | ✅ |
| Grafana | [`grafana`](../grafana/) | `dashboards` | [#24](https://github.com/devobagmbh/talos-platform-apps/issues/24) | ⬜ |

Beyond the chart's own bundle, the LGTM-A stack covers metric storage/query and
scraping with their own components: [`mimir`](../mimir/) (`metrics-storage` /
`metrics-query`, long-term store) and [`alloy`](../alloy/) (`metrics-scrape`,
collector/forwarder). The `prometheus` instance above is the local short-term path
— an instance concern the consumer wires, not a published catalog artifact.

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) (OCI granularity: component, not stack)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)

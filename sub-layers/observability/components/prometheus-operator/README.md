# Component `observability/prometheus-operator`

The **strict-B workload artifact** (talos-platform-docs ADR-0028) for the
[Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).
It ships **only** the operator controller — the `monitoring.coreos.com`
CustomResourceDefinitions are a **separate** component,
`observability/prometheus-operator-crds`. The two together form the strict-B pair:
CRDs first (the `-crds` artifact, sync-wave -1), controller after (this artifact,
sync-wave 0).

Rendered from the prometheus-community
[`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
chart in **operator-only mode**, pinned to **86.2.3** (appVersion `v0.91.0`). The
standalone `prometheus-operator` chart is DEPRECATED upstream; kube-prometheus-stack
with every instance, exporter, and scraper disabled is the maintained path to a
framework-only render.

## What ships

The Prometheus Operator controller framework, and nothing else:

- the operator controller **Deployment**,
- its **RBAC** — 2 ClusterRole + 2 ClusterRoleBinding, 1 Role + 1 RoleBinding,
  2 ServiceAccount,
- the operator **Service**,
- the **self-managed admission webhook** — 1 MutatingWebhookConfiguration +
  1 ValidatingWebhookConfiguration, plus 2 `kube-webhook-certgen` **Jobs**
  (createSecret + patchWebhook) that mint and rotate the webhook serving cert,
- 2 **ServiceMonitor** for the operator's own metrics.

Everything else the chart can emit is disabled in
[`helm/prometheus-operator.yaml`](helm/prometheus-operator.yaml): **0** CRDs (they
live in the `-crds` artifact), and **0** Prometheus / Alertmanager / Grafana /
node-exporter DaemonSet / kube-state-metrics / control-plane-scraper resources.
Those instances and exporters belong to the Prometheus **instance** component
(issue #20) and the LGTM-A stack, not to this framework.

## OCI

```text
ghcr.io/devobagmbh/talos-platform-apps/observability/prometheus-operator
```

Published registry tag `0.1.0` (the `task push` step strips the leading `v`); the
git tag is the distinct `observability/prometheus-operator-v0.1.0`.

## Sync-wave

`0` — the controller comes up after the `monitoring.coreos.com` CRDs already exist
(the `-crds` artifact at sync-wave -1).

## Consumer Argo wiring — TWO Applications (strict-B, ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app
**before** this controller:

1. **`observability/prometheus-operator-crds`** at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   `Prune=false` is the authoritative CR-cascade protection (the Helm-layer
   `helm.sh/resource-policy: keep` is not honored by Argo for its own prune
   decisions); `ServerSideApply=true` clears the 262 KB client-side annotation
   limit the large Prometheus Operator CRDs exceed.

2. **`observability/prometheus-operator`** (this artifact) at
   `argocd.argoproj.io/sync-wave: "0"`, which then reconciles against CRDs that
   already exist.

## Selector-label contract

The chart stamps a `release:` label on the rendered ServiceMonitors (and on the
operator's RBAC and Service) derived from `.Release.Name` — which, at apply time, is
the **consumer's ArgoCD Application name**, NOT `fullnameOverride` and NOT a
catalog-baked value. A consumer running the Prometheus instance with the chart
default `serviceMonitorSelectorNilUsesHelmValues: true` therefore matches only
ServiceMonitors carrying `release: <their-Application-name>`. Consumers MUST name the
workload Argo Application consistently with their Prometheus instance's selector
expectation, or relax that selector — this is a consumer composition concern, not a
catalog default.

## Namespace & Pod Security Admission

This component does **not** ship a `Namespace` object. The operator co-locates in the
shared `monitoring` namespace with the future Prometheus instance (issue #20) and the
LGTM-A stack; under the sole-claimant rule, a shared namespace and its PSA label are
the **consumer's composition concern** (Argo `managedNamespaceMetadata`), because two
artifacts declaring the same `Namespace` would make Argo report "managed by multiple
Applications".

The consumer MUST label the `monitoring` namespace:

```yaml
pod-security.kubernetes.io/enforce: restricted
```

**`restricted` is the derived level** — all three pod-bearing workloads provably
satisfy it. Evidence from the rendered `securityContext`: the operator Deployment pod
and both `kube-webhook-certgen` Job pods set `runAsNonRoot: true` +
`seccompProfile.type: RuntimeDefault` at the pod level, and every container sets
`allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]` (plus
`readOnlyRootFilesystem: true`). No pod requires host access, so `restricted` does
not reject any pod at admission.

## Capability

apis-only, **no capability** — `capabilities: []` (precedent: `lifecycle/providers`,
likewise apis-only with no capabilities, no `# TODO`). Two reasons this is a design
state, not a deferral:

- The `monitoring.coreos.com` API group is **provider-exclusive** — it is the
  Prometheus Operator's own API surface, not a swappable capability with alternative
  implementations.
- The operational capabilities a monitoring stack provides (metrics-scrape,
  metrics-storage, metrics-query, alert-routing) belong to the Prometheus **instance**
  (issue #20), not to this controller framework. This component only provisions the
  controller that reconciles those instances' CRs.

## appVersion parity

kube-prometheus-stack `86.2.3` and prometheus-operator-crds `29.0.0` both resolve to
appVersion **`v0.91.0`**. Bump the two artifacts **together**: a controller running a
newer operator version than the installed CRD schemas (or vice versa) risks CRD schema
drift — the operator may reject or mis-reconcile CRs whose schema it does not match.

## Migration

Split out of the bundled `kube-prometheus-stack` deployment in
[talos-platform-base](https://github.com/Nosmoht/talos-platform-base) (base#90) into
the strict-B pair (`-crds` + this workload). The operator is **stateless** — there is
no data migration; consumers update their Argo `Application` wiring to point at the
two new OCI artifacts (CRDs at sync-wave -1, controller at 0) in place of the old
bundle.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0015 — Monitoring-Architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

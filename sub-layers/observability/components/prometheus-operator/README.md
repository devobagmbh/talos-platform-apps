# Component `observability/prometheus-operator`

The **strict-B workload artifact** (talos-platform-docs ADR-0028) for the
[Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).
It ships **only** the operator controller — the `monitoring.coreos.com`
CustomResourceDefinitions are a **separate** component,
`observability/prometheus-operator-crds`. The two together form the strict-B pair:
CRDs first (the `-crds` artifact, sync-wave -1), controller after (this artifact,
sync-wave 0).

Vendored verbatim from the upstream
[`prometheus-operator/prometheus-operator`](https://github.com/prometheus-operator/prometheus-operator)
repository, tag **v0.91.0**, directory `example/rbac/prometheus-operator/`. Delivered
as raw vendored manifests (`kind: manifests`, no Helm reference); re-vendor from the
matching upstream tag on every version bump.

Two deliberate deltas from the upstream base:

- namespaced objects are moved from `default` to `monitoring` (consumer-overlayable;
  no `Namespace` object ships — the `monitoring` namespace is consumer-owned, see
  [Namespace & Pod Security Admission](#namespace--pod-security-admission));
- the operator and `prometheus-config-reloader` images are **digest-pinned** (issue
  #175 supply-chain hardening) — tags stay upstream-default `v0.91.0`, the `@sha256`
  digest is the authoritative pull reference. Re-verify on each bump
  (`oras manifest fetch --descriptor quay.io/.../prometheus-operator:<tag>`).

This component is defined by *what it ships* (the operator controller + RBAC +
Service, **0** CRDs — the strict-B `task validate:crd-split` gate asserts 0 CRDs
here), not by the source it is vendored from.

## What ships

The Prometheus Operator controller framework, and nothing else:

- the operator controller **Deployment**,
- its **RBAC** — 1 ClusterRole + 1 ClusterRoleBinding + 1 ServiceAccount,
- the operator **Service** (headless, port 8080),
- 1 **ServiceMonitor** for the operator's own metrics.

**0** CRDs (they live in the `-crds` artifact — the strict-B gate asserts 0 here),
**0** Prometheus / Alertmanager / Grafana / node-exporter DaemonSet /
kube-state-metrics / control-plane-scraper resources, and **no admission webhook**
(a consumer opt-in — see [Admission webhook](#admission-webhook)). Those instances and
exporters belong to the Prometheus **instance** component (issue #20) and the LGTM-A
stack, not to this framework.

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

## Admission webhook

This artifact ships **no** admission webhook. Upstream's optional `PrometheusRule` /
`AlertmanagerConfig` validating webhook (`example/admission-webhook/`) needs a TLS
cert source (cert-manager `Certificate`), which would make cert-manager a **fixed
dependency** of a catalog framework component — deliberately avoided so the component
stays dependency-free. Without the webhook, a malformed `PrometheusRule` or
`AlertmanagerConfig` is **admitted** and surfaces later as an operator reconcile error
rather than being rejected at admission time.

A consumer that wants admission-time validation opts in **in the consumer repo** by
wiring the webhook (with its own cert source) alongside this component — it is not a
catalog default.

## Selector labels

The operator `Service` and its `ServiceMonitor` carry the stable upstream
`app.kubernetes.io/{name,component}` labels (`name: prometheus-operator`,
`component: controller`) — **not** a Helm `.Release.Name`-derived `release:` label. A
consumer running a Prometheus instance that selects ServiceMonitors by label MUST
match on these `app.kubernetes.io` labels (or relax its selector). This is a consumer
composition concern, not a catalog default.

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

**`restricted` is the derived level** — the operator provably satisfies it. Evidence
from the rendered `securityContext`: the operator Deployment pod sets
`runAsNonRoot: true` + `runAsUser: 65534` + `seccompProfile.type: RuntimeDefault` at
the pod level, and the container sets `allowPrivilegeEscalation: false` +
`capabilities.drop: [ALL]` + `readOnlyRootFilesystem: true`. No pod requires host
access, so `restricted` does not reject it at admission.

## Security posture

The operator `ClusterRole` carries the upstream prometheus-operator default grant set
— broad verbs on the `monitoring.coreos.com` resources it owns, plus cluster-wide verbs
on the core `Secret` and `ConfigMap` objects it manages for the Prometheus and
Alertmanager instances it reconciles. These grants are **inherent to the operator's
reconcile contract**, not introduced by this catalog component, and the upstream base
exposes no narrower scoping at this version. A consumer MAY further constrain the
operator's blast radius with a `NetworkPolicy` and namespace isolation. No long-lived
keys or secret material ship in this artifact.

## Capability

api-surface-only, **no capability** — `capabilities: []` (precedent: `lifecycle/providers`,
likewise api-surface-only with no capabilities, no `# TODO`). Two reasons this is a design
state, not a deferral:

- The `monitoring.coreos.com` API group is **provider-exclusive** — it is the
  Prometheus Operator's own API surface, not a swappable capability with alternative
  implementations.
- The operational capabilities a monitoring stack provides (metrics-scrape,
  metrics-storage, metrics-query, alert-routing) belong to the Prometheus **instance**
  (issue #20), not to this controller framework. This component only provisions the
  controller that reconciles those instances' CRs.

## Version parity

This workload and the `-crds` artifact are both vendored from prometheus-operator
**v0.91.0**. Bump the two artifacts **together**: a controller running a newer operator
version than the installed CRD schemas (or vice versa) risks CRD schema drift — the
operator may reject or mis-reconcile CRs whose schema it does not match.

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

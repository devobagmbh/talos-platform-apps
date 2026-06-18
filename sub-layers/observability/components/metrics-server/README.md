# Component `observability/metrics-server`

[metrics-server](https://github.com/kubernetes-sigs/metrics-server) — the
Kubernetes **Resource Metrics API** (`metrics.k8s.io`). It scrapes CPU/memory
from each node's Kubelet and serves them through the aggregation layer, which is
what powers the Horizontal Pod Autoscaler and `kubectl top`. Migrated out of the
`talos-platform-base` substrate into the catalog as an independently versioned
OCI artifact (ADR-0009); base pinned chart `3.12.2`, this component upgrades to
`3.13.1`.

It implements the `hpa-metrics` capability (`catalog/capability-index.yaml`,
`swap_class: drop-in`): a consumer can substitute another Resource-Metrics-API
implementation without changing selectors or config shapes.

## Contents

A `kind: helm` wrapper over the `metrics-server` chart
(`https://kubernetes-sigs.github.io/metrics-server/`, version `3.13.1`,
appVersion `0.8.1`) plus `manifests/00-namespace.yaml`:

- `Deployment` (`metrics-server`) + `Service` + `ServiceAccount` and the
  aggregation `APIService` `v1beta1.metrics.k8s.io`, with the chart's read RBAC.
- A dedicated `metrics-server` `Namespace` (the base migration relocated it from
  `kube-system` — "capability-first refactor").

The image is pinned to the chart's appVersion
(`registry.k8s.io/metrics-server/metrics-server:v0.8.1`) — never `:latest`.

## Talos-required values (set explicitly)

Chart `3.13.1` already carries the Talos-required kubelet flags in its
`defaultArgs` and a restricted-compliant container `securityContext`, but the
catalog sets them **explicitly** (explicit-not-inherited) so a future chart bump
cannot silently drop them:

- `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname` and
  `--kubelet-use-node-status-port` — required on Talos, where the Kubelet does
  not serve on the default port.
- `apiService.insecureSkipTLSVerify: true` — metrics-server serves a self-signed
  cert and there is no cert-manager TLS wiring for it in base or here, so the
  aggregation layer must skip verification. This is the correct and complete
  posture for standard Talos.
- `podSecurityContext` (`runAsNonRoot` + `seccompProfile: RuntimeDefault`) — the
  chart leaves the pod-level context empty; set here so the rendered pod template
  satisfies `enforce: restricted` at the pod scope (the container context already
  sets the container-level predicates).

Replica count / HA topology is **not** pinned here — it is a consumer-overlay
concern (cluster-specific per AGENTS.md §Hard Constraints); the catalog leaves it
at the chart default (`1`).

## Namespace & Pod Security

The component ships a dedicated `metrics-server` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule, ADR-0032) carrying
`pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels. metrics-server is a
stateless aggregator with no host-access need, so `restricted` is the
unconditional posture — confirmed against the rendered pod template (pod
`runAsNonRoot` + `seccompProfile: RuntimeDefault`; container
`allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]`).

The catalog ships **only** the `enforce` level and the ownership labels.

The chart's RBAC (read `ClusterRole`s + `ClusterRoleBinding`s + a `kube-system`
`RoleBinding` for `extension-apiserver-authentication`) grants cluster-wide
`get/list/watch` on `nodes`, `nodes/metrics`, and `pods`, plus `namespaces` and
`configmaps` for aggregation-layer health. The `namespaces`/`configmaps` grants
are upstream chart defaults (kubernetes-sigs `metrics-server` 3.13.1) and are not
narrowable at the helm-wrapper layer — noted here for consumers auditing
cluster RBAC.

## Consumer obligations (out of scope here)

Per ADR-0032, the **consumer** adds the following in its Argo overlay — this
catalog component ships none of them:

- **Namespace** (Argo `managedNamespaceMetadata` or a patch on the shipped
  Namespace): the `pod-security.kubernetes.io/enforce-version` pin (its cluster's
  Kubernetes minor), the `audit`/`audit-version` and `warn`/`warn-version`
  modes, and the PNI trust-anchor labels —
  `platform.io/provide.hpa-metrics`, `platform.io/provide.monitoring-scrape`,
  `platform.io/network-interface-version`, `platform.io/network-profile`.
- **Pod template** (via a consumer Helm values overlay) — the
  `platform.io/capability-provider.hpa-metrics` and
  `platform.io/capability-provider.monitoring-scrape` pod labels (coupled to the
  namespace `provide.*` trust anchors).
- **Service** (via a consumer Helm values overlay) — the
  `platform.io/capability-endpoint.hpa-metrics` and
  `platform.io/capability-protocol.hpa-metrics` annotations.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Sync-wave

`0` — catalog default. metrics-server has no catalog-internal dependencies and
needs only the Kubernetes control-plane API, so it deploys early (like
`observability/hubble`). A consumer needing it earlier at bootstrap deploys it in
an earlier wave from its own overlay.

**Bootstrap considerations (consumer-relevant):** the aggregated `APIService`
`v1beta1.metrics.k8s.io` is registered as soon as Argo applies it but returns
`503` until the Deployment Pod is Ready — a transient, self-healing window of
roughly the Pod start-up time. `kubectl top` and the HPA simply retry; a consumer
component that requires HPA metrics *at* bootstrap should pin itself to a later
wave. Replica count defaults to the chart's `1`; a consumer needing
metrics-API availability across Pod restarts (rolling image updates) should set
`replicas: 2` (and/or a `PodDisruptionBudget`) in its Argo values overlay.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/metrics-server:0.1.0
```

OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is `observability/metrics-server-v0.1.0`
(kept distinct — registry tag vs. SemVer git tag).

## Related ADRs

- ADR-0024 — Customization Contract v2 (freeze-line)
- ADR-0032 — Namespace / PSA ownership model
- ADR-0009 — Platform Layer Model (OCI granularity)

# Component `observability/kube-state-metrics`

[kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) — a
listening service that generates **Kubernetes object-state metrics** (the
`kube_*` series: Deployment replica states, Pod phases, Node conditions,
DaemonSet/StatefulSet rollout status, …) and exposes them on a Prometheus
`/metrics` endpoint. It does not store or alert; it is a stateless exporter that
the cluster's **Grafana Alloy** scrapes (`observability/alloy`). Published as an
independently versioned OCI artifact (ADR-0009).

This component provides **no swappable capability** (`compatibility.yaml`
`provides[].capabilities: []`). kube-state-metrics is the canonical, sole provider
of the `kube_*` object-state series over a Prometheus `/metrics` endpoint — there
is no drop-in alternative implementing the same interface, so it is an apis-only
component (precedent: `lifecycle/providers`). It is distinct from
`observability/alloy`, which implements the `metrics-scrape` capability (the
*scraper*); kube-state-metrics is the *source* being scraped.

## Contents

A `kind: helm` wrapper over the `kube-state-metrics` chart
(`https://prometheus-community.github.io/helm-charts`, version `7.5.1`,
appVersion `2.19.1`) plus `manifests/00-namespace.yaml`:

- `Deployment` (`kube-state-metrics`) + `Service` + `ServiceAccount`, with the
  chart's cluster-wide read `ClusterRole` + `ClusterRoleBinding`.
- A dedicated `kube-state-metrics` `Namespace` (the chart ships none).

The render is **single-container** — the optional `kube-rbac-proxy` sidecar is
kept at its chart default (`kubeRBACProxy.enabled: false`). The image is pinned to
the chart's appVersion
(`registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.19.1`) — never
`:latest`.

## Security posture (pinned explicitly)

Chart `7.5.1` already ships a restricted-compliant securityContext, but the
catalog pins it **explicitly** (explicit-not-inherited) so a future chart bump
cannot silently weaken it. Note the chart's value key names are chart-specific and
differ from `metrics-server`:

- Pod-level key is `securityContext:` (with an `enabled:` gate, NOT
  `podSecurityContext:`) — `enabled: true`, `runAsNonRoot: true`,
  `runAsUser: 65534`, `runAsGroup: 65534`, `fsGroup: 65534`,
  `seccompProfile.type: RuntimeDefault`.
- Container-level key is `containerSecurityContext:` —
  `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]`, plus `runAsNonRoot: true` + `runAsUser: 65534`
  (the chart omits `runAsNonRoot` at container scope, so it is added explicitly so
  every rendered container satisfies the restricted check at container scope, not
  merely by inheritance from the pod).

Replica count / HA topology is **not** pinned here — it is a consumer-overlay
concern (cluster-specific per AGENTS.md §Hard Constraints); the catalog leaves it
at the chart default (`1`).

## Namespace & Pod Security

The component ships a dedicated `kube-state-metrics` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule, ADR-0027) carrying
`pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels. kube-state-metrics is
a stateless exporter with no host-access need, so `restricted` is the
unconditional posture — confirmed against the rendered pod template (pod
`runAsNonRoot` + `seccompProfile: RuntimeDefault`; container
`allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]`).

The catalog ships **only** the `enforce` level and the ownership labels.

## Cluster-wide read RBAC (consumer-relevant)

The chart ships a `ClusterRole` + `ClusterRoleBinding` granting cluster-wide
`get/list/watch` on most core and apps/batch/networking object kinds (Pods, Nodes,
Deployments, ReplicaSets, DaemonSets, StatefulSets, Jobs, CronJobs, Services,
Ingresses, ConfigMaps, Secrets metadata, …) — this read access over the whole
cluster is **inherent** to kube-state-metrics generating object-state series and
is **not narrowable** at the Helm-wrapper layer. Consumers auditing cluster RBAC
should note this broad read grant.

## Consumer obligations (out of scope here)

Per ADR-0027, the **consumer** adds the following in its Argo overlay — this
catalog component ships none of them:

- **Namespace** (Argo `managedNamespaceMetadata` or a patch on the shipped
  Namespace): the `pod-security.kubernetes.io/enforce-version` pin (its cluster's
  Kubernetes minor), the `audit`/`audit-version` and `warn`/`warn-version` modes,
  and the PNI trust-anchor labels.
- **Scrape configuration** — Alloy scrapes the `/metrics` endpoint via its own
  config; no `ServiceMonitor`/`PodMonitor` CR is shipped here.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Sync-wave

`0` — catalog default. kube-state-metrics has no catalog-internal dependencies and
needs only the Kubernetes control-plane API, so it deploys early (like
`observability/metrics-server`). A consumer needing it earlier at bootstrap
deploys it in an earlier wave from its own overlay.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/kube-state-metrics:0.1.0
```

OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is
`observability/kube-state-metrics-v0.1.0` (kept distinct — registry tag vs. SemVer
git tag).

## Related ADRs

- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0027 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0027-namespace-psa-ownership.md)
- [ADR-0028 — Strict-B CRD management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — N/A here (the chart ships no CRDs).
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

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
is no drop-in alternative implementing the same interface, so it is an api-surface-only
component (precedent: `lifecycle/providers`). It is distinct from
`observability/alloy`, which implements the `metrics-scrape` capability (the
*scraper*); kube-state-metrics is the *source* being scraped.

## Contents

A `kind: helm` wrapper over the `kube-state-metrics` chart
(`https://prometheus-community.github.io/helm-charts`, version `8.4.1`,
appVersion `2.20.0`) plus `manifests/00-namespace.yaml`:

- `Deployment` (`kube-state-metrics`) + `Service` + `ServiceAccount`, with the
  chart's cluster-wide read `ClusterRole` + `ClusterRoleBinding`.
- A `ConfigMap` (`kube-state-metrics-customresourcestate-config`) carrying an
  **empty but valid** CustomResourceState spec, mounted read-only at
  `/etc/customresourcestate` and passed to the exporter via
  `--custom-resource-state-config-file` — see
  [CustomResourceState metrics](#customresourcestate-metrics-kube_customresource_)
  below.
- A dedicated `kube-state-metrics` `Namespace` (the chart ships none).

The render is **single-container** — the optional `kube-rbac-proxy` sidecar is
kept at its chart default (`kubeRBACProxy.enabled: false`). The image is pinned to
the chart's appVersion
(`registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0`) — never
`:latest`.

## Security posture (pinned explicitly)

Chart `8.4.1` already ships a restricted-compliant securityContext, but the
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
(`manifests/00-namespace.yaml`, sole-claimant rule, ADR-0032) carrying
`pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels. kube-state-metrics is
a stateless exporter with no host-access need, so `restricted` is the
unconditional posture — confirmed against the rendered pod template (pod
`runAsNonRoot` + `seccompProfile: RuntimeDefault`; container
`allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]`).

The catalog ships **only** the `enforce` level and the ownership labels.

## Cluster-wide read RBAC (consumer-relevant)

The chart ships a `ClusterRole` + `ClusterRoleBinding` granting cluster-wide
**`list`/`watch` only** (no `get`, no write verbs) on most core and
apps/batch/networking object kinds (Pods, Nodes, Deployments, ReplicaSets,
DaemonSets, StatefulSets, Jobs, CronJobs, Services, Ingresses, ConfigMaps,
Secrets, …) — this read access over the whole cluster is **inherent** to
kube-state-metrics generating object-state series and is **not narrowable** at the
Helm-wrapper layer. Consumers auditing cluster RBAC should note this broad read
grant. Two aspects are consumer-owned mitigations:

- **Secret enumeration** — the `secrets` grant is `list`/`watch` **only** (no
  `get`), so kube-state-metrics enumerates Secret names/labels/annotations to emit
  the `kube_secret_*` series but **cannot read Secret values**. A consumer that
  considers even metadata enumeration unacceptable disables it in its Argo overlay
  via the exporter's `--resources=` arg (omit `secrets`), trading away the
  `kube_secret_*` metrics.
- **ServiceAccount token** — the pod mounts its SA token to call the API server. On
  Kubernetes ≥ 1.22 / Talos this is a **bound, short-TTL projected token**
  (BoundServiceAccountTokenVolume), not a long-lived Secret token, so a compromised
  pod holds only a time-bounded credential scoped to the read-only grant above.

Enabling the CustomResourceState plumbing adds exactly one rule to that
`ClusterRole`: `list`/`watch` on
`apiextensions.k8s.io/customresourcedefinitions` (chart-driven, via
`rbac.customResourceState.createClusterRoleRules`). It grants **no** read access to
any CustomResource itself — the catalog never sets `rbac.extraRules` and never
grants `apiGroups: ["*"]`, which would be cluster-wide read on every present and
future CRD. CR read permission is consumer-owned and per-apiGroup (next section).

## CustomResourceState metrics (`kube_customresource_*`)

The artifact ships the **CustomResourceState (CRS) plumbing** enabled with an empty
baked spec: the `kube-state-metrics-customresourcestate-config` `ConfigMap`, the
read-only volume + mount at `/etc/customresourcestate`, the
`--custom-resource-state-config-file=/etc/customresourcestate/config.yaml` arg, and
the CRD read grant. The baked `config.yaml` is

```yaml
spec:
  resources: []
```

which is a valid spec defining zero custom metrics, so the exporter runs unchanged
and emits only the built-in `kube_*` series when a consumer replaces nothing.

The plumbing MUST ship enabled because the component is published as a pre-rendered
Kustomize base (ADR-0024): a consumer patch can change objects and fields that
exist, but cannot conjure a ConfigMap, a volume, a mount and a CLI flag that were
never rendered. The catalog bakes **no** rules for the platform's own CRDs — a
shipped rule set would need RBAC for CRD groups a given cluster may not have, and
pinning against upstream CR-schema drift.

The file is declared in `customization.yaml` as the component's single
`optional.config_files` entry (`provided_refs.config`, DR-0005), so it is a
versioned contract surface: renaming it, removing it, or changing its baked
`default` is a **breaking** change requiring a major bump and a migration note.

Emitting `kube_customresource_*` series takes **two** consumer-side steps, both in
the consumer's Argo overlay.

### 1. Replace the spec (kustomize patch)

Patch the shipped `ConfigMap` — never create or edit the object directly: it is part
of the signed base, so Argo reconciles a direct edit away.

```yaml
# consumer Application source (consumer repo)
source:
  repoURL: oci://<registry>/observability/kube-state-metrics
  targetRevision: <tag>
  path: "."
  kustomize:
    patches:
      - target:
          kind: ConfigMap
          name: kube-state-metrics-customresourcestate-config
        patch: |
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: kube-state-metrics-customresourcestate-config
          data:
            config.yaml: |
              spec:
                resources:
                  - groupVersionKind:
                      group: <apiGroup>
                      version: <version>
                      kind: <Kind>
                    metrics:
                      - name: <metric_suffix>
                        help: "<help text>"
                        each:
                          type: Gauge
                          gauge:
                            path: [status, <field>]
```

The spec format is upstream's — see
[Custom Resource State Metrics](https://github.com/kubernetes/kube-state-metrics/blob/main/docs/metrics/extend/customresourcestate-metrics.md).
Series are named `kube_customresource_<metric_suffix>` by default.

**Reload:** no pod restart is needed. The exporter watches the file and restarts its
collectors in-process on a change (`internal/wrapper.go` at `v2.20.0`), and that
watch fires on the kubelet's projected-volume update — verified on a local cluster in
both directions (spec added, spec reverted) with the container's restart count
staying `0`. Expect a delay of the kubelet sync period (up to ~1 minute) plus the
exporter's own 3-second port-release wait; restart the `Deployment` only if a
replaced spec has not taken effect.

### 2. Grant CR read access (additive ClusterRole + binding)

Upstream requires `list`/`watch` on the CRD **and** on each resource the spec names.
The artifact carries the former only, so the consumer adds an **additive**
`ClusterRole` + `ClusterRoleBinding` onto the shipped `kube-state-metrics`
`ServiceAccount`, one rule per apiGroup the spec names:

```yaml
# consumer-owned, additive — NOT shipped by this component
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-state-metrics-customresource-read
rules:
  - apiGroups: ["<apiGroup>"]
    resources: ["<plural>"]
    verbs: ["list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-state-metrics-customresource-read
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics-customresource-read
subjects:
  - kind: ServiceAccount
    name: kube-state-metrics
    namespace: kube-state-metrics
```

Without the grant the exporter still runs, but no series appear for that kind — its
`list`/`watch` on the CR is denied.

## Consumer obligations (out of scope here)

Per ADR-0032, the **consumer** adds the following in its Argo overlay — this
catalog component ships none of them:

- **Namespace** (Argo `managedNamespaceMetadata` or a patch on the shipped
  Namespace): the `pod-security.kubernetes.io/enforce-version` pin (its cluster's
  Kubernetes minor), the `audit`/`audit-version` and `warn`/`warn-version` modes,
  and the PNI trust-anchor labels.
- **Scrape configuration** — Alloy scrapes the `/metrics` endpoint via its own
  config; no `ServiceMonitor`/`PodMonitor` CR is shipped here.
- **CustomResourceState spec + its CR read RBAC** — both consumer-owned; see
  [CustomResourceState metrics](#customresourcestate-metrics-kube_customresource_).
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

## Migration

Chart `7.5.1` → `8.4.1` (appVersion `2.19.1` → `2.20.0`) plus the CRS plumbing. The
chart bump alone is render-neutral beyond the image tag and chart/version labels —
verified by rendering both versions against the catalog's own values (the only other
deltas are two dropped empty `httpHeaders:` keys in the probes and one blank line in
the `Service`); no value key this component sets is renamed or removed.

Two consumer-visible changes come from the CRS plumbing:

- The pod template now carries a **`volumes:` array where it previously had none**
  (`customresourcestate-config`, projecting the shipped ConfigMap), and the
  container a matching read-only `volumeMounts` entry. Two consumer overlay shapes
  break:
  - A consumer that injected its own volumes with `op: add` on the **whole array**
    (`path: /spec/template/spec/volumes`) — the only form available while the array
    was absent, since the append form `/-` needs an existing array. RFC 6902 §4.1
    makes `add` on an existing member a **replace**, so that patch now drops the
    baked `customresourcestate-config` volume while the container keeps its
    `volumeMounts` entry and the `--custom-resource-state-config-file` arg: the pod
    does not start. Switch to per-element append
    (`op: add, path: /spec/template/spec/volumes/-`) or a named strategic-merge
    patch. The same applies to the parallel `volumeMounts` path.
  - A consumer patching by **index** (`/spec/template/spec/volumes/0`) — index `0`
    is now the catalog's volume, not the consumer's.
- The `ClusterRole` gains `list`/`watch` on
  `apiextensions.k8s.io/customresourcedefinitions`.

No data migration: the exporter is stateless, and the baked empty spec emits no new
series.

## Related ADRs

- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0032 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0032-catalog-namespace-psa-ownership.md)
- [ADR-0028 — Strict-B CRD management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — N/A here (the chart ships no CRDs).
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

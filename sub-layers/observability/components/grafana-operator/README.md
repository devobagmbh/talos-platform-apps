# Component `observability/grafana-operator`

The **strict-B workload artifact** (talos-platform-docs ADR-0028) for the
[Grafana Operator](https://github.com/grafana/grafana-operator). It ships **only** the
operator controller — the `grafana.integreatly.org` CustomResourceDefinitions are a
**separate** component, `observability/grafana-operator-crds`. The two together form
the strict-B pair: CRDs first (the `-crds` artifact, sync-wave -1), controller after
(this artifact, sync-wave 0).

Rendered from the upstream
[`grafana-operator`](https://github.com/grafana/grafana-operator/tree/master/deploy/helm/grafana-operator)
chart, pinned to **5.24.0** (app version `v5.24.0`), with default values plus an
explicit security-context pin set (see [Values](#values)). The chart emits the
controller framework only — there is no separate operator-only mode to enable.

The chart source is a deliberate but **swappable** implementation detail: this
component is defined by *what it ships* (the operator controller + RBAC + Service,
**0** CRDs — the render-parity contract), not by the chart it renders from. A
**chart→chart** swap stays localized to
[`helm/grafana-operator.yaml`](helm/grafana-operator.yaml) (`chart` / `repo` /
`version` + values), with no change to the OCI path, the capability contract, or the
consumer's Argo wiring.

## What ships

The Grafana Operator **controller only**, and nothing else:

- the operator controller **Deployment**,
- its **RBAC** — 1 ClusterRole + 1 ClusterRoleBinding (cluster-scoped reconcile of
  `grafana.integreatly.org` resources), 1 Role + 1 RoleBinding (namespaced leader
  election + own config), 1 ServiceAccount,
- the operator metrics **Service**.

It does **not** ship a Grafana instance, and it does **not** ship any
`grafana.integreatly.org` custom resources — no `Grafana`, `GrafanaDashboard`,
`GrafanaDatasource`, `GrafanaFolder`, `GrafanaAlertRuleGroup`, or any other CR. Those
are **consumer CRs** the running operator reconciles; authoring them is a
consumer-cluster composition concern, never part of this controller artifact. The CRD
schemas those CRs validate against ship in the `-crds` artifact, not here.

The render carries **0** CustomResourceDefinitions (they live in the `-crds` artifact),
**0** Namespace, **0** ServiceMonitor, **0** webhook configurations, and **0** Jobs.

## OCI

```text
ghcr.io/devobagmbh/talos-platform-apps/observability/grafana-operator
```

Published registry tag `0.1.0` (the `task push` step strips the leading `v`); the git
tag is the distinct `observability/grafana-operator-v0.1.0`.

## Sync-wave

`0` — the controller comes up after the `grafana.integreatly.org` CRDs already exist
(the `-crds` artifact at sync-wave -1).

## Consumer Argo wiring — TWO Applications (strict-B, ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — the `-crds` app **before**
this controller:

1. **`observability/grafana-operator-crds`** at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   `Prune=false` is the authoritative CR-cascade protection (the Helm-layer
   `helm.sh/resource-policy: keep` is not honored by Argo for its own prune decisions);
   `ServerSideApply=true` clears the 262 KB client-side annotation limit large CRDs may
   exceed.

2. **`observability/grafana-operator`** (this artifact) at
   `argocd.argoproj.io/sync-wave: "0"`, which then reconciles against CRDs that already
   exist.

## Values

The component renders from chart defaults plus an explicit pin set in
[`helm/grafana-operator.yaml`](helm/grafana-operator.yaml):

| Key | Value | Reason |
|-----|-------|--------|
| `crds.immutable` | `true` | Strict-B contract made visible. At the chart default (immutable), CRDs are referenced from `crds/` and the workload renders **0** CustomResourceDefinitions. Written explicitly; **never** set `false` (a mutable render emits CRDs into this workload — a strict-B violation). |
| `podSecurityContext.seccompProfile.type` | `RuntimeDefault` | The chart default `podSecurityContext` is `{}` (no seccomp profile), which PSA-`restricted` admission rejects. Pinned so the operator pod is admissible under the consumer's `restricted` namespace label. |
| `securityContext.runAsNonRoot` | `true` | PSA-`restricted` control. Matches the chart default; pinned explicitly as the producing values-pin for the rendered control. |
| `securityContext.readOnlyRootFilesystem` | `true` | Read-only container root filesystem. Matches the chart default; pinned explicitly. |
| `securityContext.allowPrivilegeEscalation` | `false` | PSA-`restricted` control. Matches the chart default; pinned explicitly. |
| `securityContext.capabilities.drop` | `[ALL]` | PSA-`restricted` control. Matches the chart default; pinned explicitly. |

## Namespace & Pod Security Admission

This component does **not** ship a `Namespace` object. The operator co-locates in the
shared `monitoring` namespace with the Prometheus operator and the rest of the
observability stack; under the sole-claimant rule, a shared namespace and its PSA label
are the **consumer's composition concern** (Argo `managedNamespaceMetadata`), because
two artifacts declaring the same `Namespace` would make Argo report "managed by multiple
Applications".

The consumer MUST label the `monitoring` namespace:

```yaml
pod-security.kubernetes.io/enforce: restricted
```

**`restricted` is the required level**, and the rendered pod provably satisfies it. The
evidence is in the pinned `securityContext` (see [Values](#values)): the operator
Deployment pod sets `seccompProfile.type: RuntimeDefault` (pod level) and the container
sets `runAsNonRoot: true` + `readOnlyRootFilesystem: true` +
`allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]`. No pod uses a
Baseline-forbidden field (no hostPath, no host namespaces, no privileged container, no
host port), so `restricted` rejects no pod at admission.

Because this artifact ships **no** `Namespace` object, catalog CI does **not** verify
PSA conformance for it — the `conformance.pod_security` gate fires only when an artifact
declares a namespace with a PSA label. PSA conformance for this component is therefore
README-documented (the pinned `securityContext` above is the evidence) and verified at
**live consumer admission** against the namespace `enforce: restricted` label.

## Security posture

The operator `ClusterRole` carries the upstream chart's reconcile grant set — verbs on
the `grafana.integreatly.org` resources the operator owns, plus the core objects
(`Secret`, `ConfigMap`, `Deployment`, `Service`, …) it manages for the Grafana
instances it reconciles. These grants are **inherent to the operator's reconcile
contract**, not introduced by this catalog component. A consumer MAY further constrain
the operator's blast radius with a `NetworkPolicy` and namespace isolation. No
long-lived keys or secret material ship in this artifact — the operator authenticates
to the API server with a projected ServiceAccount token (chart default `kubeAuth`
audience `operator.grafana.com`, rotated hourly).

## Capability

api-surface-only, **no capability** — `capabilities: []` (precedent:
`observability/prometheus-operator` and `lifecycle/providers`, likewise api-surface-only
with no capabilities, no `# TODO`). This is a design state, not a deferral: the
operational `dashboards` capability belongs to a running **Grafana instance**
(`observability/grafana`, issue #24), not to this controller framework. The
grafana-operator reconciles Grafana instances via the `grafana.integreatly.org` CRDs —
it is not itself a dashboard frontend — so assigning `dashboards` here would be
incorrect, and no other index capability fits.

## Migration

The operator is **stateless** — there is no data migration. The Grafana instances and
dashboards it manages are consumer `grafana.integreatly.org` CRs whose lifecycle is
independent of this controller artifact; replacing the controller version reconciles
the same CRs against the matching CRD schemas (bump this workload and the `-crds`
artifact together to avoid schema drift).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0015 — Monitoring-Architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

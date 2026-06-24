# Component `observability/grafana-operator-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[Grafana Operator](https://grafana.github.io/grafana-operator/). It ships **only**
the 13 `grafana.integreatly.org` `v1beta1` CustomResourceDefinitions — the Grafana
Operator workload (Deployment, RBAC, Service) is a **separate** component,
`observability/grafana-operator`. The two together form the strict-B pair: CRDs
first (this artifact, sync-wave -1), operator after (sync-wave 0).

The CRDs are sourced verbatim from the upstream `grafana-operator` Helm chart
**5.24.0**. The grafana-operator chart has **no** dedicated CRDs-only chart and
renders its CRDs through chart templates gated on `crds.immutable`, so this
component is delivered as **raw vendored manifests** (`kind: manifests`) extracted
once from the main chart, not as a Helm reference.

## What ships

Exactly 13 cluster-scoped CustomResourceDefinitions, all in the
`grafana.integreatly.org` API group, served version `v1beta1`:

- `grafanas.grafana.integreatly.org`
- `grafanadashboards.grafana.integreatly.org`
- `grafanadatasources.grafana.integreatly.org`
- `grafanafolders.grafana.integreatly.org`
- `grafanaalertrulegroups.grafana.integreatly.org`
- `grafanacontactpoints.grafana.integreatly.org`
- `grafanalibrarypanels.grafana.integreatly.org`
- `grafanamanifests.grafana.integreatly.org`
- `grafanamutetimings.grafana.integreatly.org`
- `grafananotificationpolicies.grafana.integreatly.org`
- `grafananotificationpolicyroutes.grafana.integreatly.org`
- `grafananotificationtemplates.grafana.integreatly.org`
- `grafanaserviceaccounts.grafana.integreatly.org`

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD
schemas. The Grafana Operator workload Namespace (and its Pod Security Admission
`enforce` label) stays with the `observability/grafana-operator` workload artifact;
CRDs are cluster-scoped and require no namespace.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the operator:

1. **`observability/grafana-operator-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting a CRD (and cascading the consumer's live `Grafana` /
     `GrafanaDashboard` / `GrafanaDatasource` CRs, which would tear down the
     managed Grafana instances and dashboards) when the source removes it. The
     Helm-layer `helm.sh/resource-policy: keep` annotation is **not** honored by
     Argo for its own prune decisions, so `Prune=false` carries the guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit — the Grafana Operator CRDs are large — and is the convention for the
     strict-B `-crds` apps.

2. The workload Application **`observability/grafana-operator`** at sync-wave 0,
   which then comes up against CRDs that already exist (the
   `grafana.integreatly.org` API group is registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`task validate:crd-split`:
`kind: CustomResourceDefinition` count **> 0** here, **== 0** in the workload
artifact). Its workload counterpart is `observability/grafana-operator`.

## Regeneration / drift

The vendored manifest (`manifests/00-grafana-operator-crds.yaml`) was generated
once from chart `grafana-operator` 5.24.0 via:

```sh
helm template grafana-operator grafana-operator \
  --repo https://grafana.github.io/helm-charts \
  --version 5.24.0 \
  --set crds.immutable=false \
  | yq -y 'select(.kind == "CustomResourceDefinition")'
```

`--set crds.immutable=false` makes the chart render the CRDs through
`templates/crds.yaml` regardless of the chart's CRD-delivery layout; the extracted
objects are the same 13 schemas the operator manages either way.

The source chart+version (grafana-operator 5.24.0) is the **drift anchor**. A chart
version bump requires re-vendoring this file **and** an
`observability/grafana-operator-crds` version bump. It MUST be bumped **together**
with the `observability/grafana-operator` workload chart pin — the workload chart
version and this vendored-CRD anchor are coupled (both `grafana-operator 5.24.0`
today). No mechanical drift check exists, consistent with the
`observability/prometheus-operator-crds` and `secrets/external-secrets-crds`
README-only precedent; the coupling is upheld by convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because the
consumer app runs `Prune=false`, fields the upstream removes are **not** auto-pruned
from the cluster; removal needs manual intervention. A version bump is a separate
reviewed change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The
`grafana.integreatly.org` CRDs are the API surface (schemas) of the Grafana
Operator's own exclusive API group, not a swappable operational capability: no
alternative implementation satisfies the same group/version contract. The
operational `dashboards` capability belongs to a running Grafana **instance** (the
`observability/grafana` component), not to this CRD bundle or to the operator
controller. Carrying `capabilities: []` here is the deliberate design (precedent:
`observability/prometheus-operator-crds` and `secrets/external-secrets-crds`,
likewise api-surface-only with no capability), NOT a deferral — so no `# TODO:`.

## Sync-wave

`-1` — the CRDs land before the operator workload at wave 0, so the
`grafana.integreatly.org` API group is registered before the operator starts
reconciling `Grafana` / `GrafanaDashboard` / `GrafanaDatasource` CRs.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/grafana-operator-crds:vX.Y.Z
```

The git tag is `observability/grafana-operator-crds-vX.Y.Z` (first release
`v0.1.0`); `task push` strips the leading `v`, so the OCI registry tag is the bare
SemVer. The workload `observability/grafana-operator` carries
`requires: {observability/grafana-operator-crds: ">=v0.1.0"}` and
`crds.immutable: true` (its companion strict-B values) — it renders zero CRDs and
depends on this artifact landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

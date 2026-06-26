# Component `automation/actions-runner-controller-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for GitHub's
[Actions Runner Controller](https://github.com/actions/actions-runner-controller)
(ARC). It ships **only** the 4 `actions.github.com` CustomResourceDefinitions — the
ARC controller workload (Deployment, RBAC, Namespaces, NetworkPolicies) is a
**separate** component, `automation/actions-runner-controller`. The two together form
the strict-B pair: CRDs first (this artifact, sync-wave -1), controller after
(sync-wave 0).

The CRDs are sourced verbatim from the upstream
`gha-runner-scale-set-controller` Helm chart **0.14.2** (appVersion `0.14.2`). That
chart ships its CRDs as raw files under the chart's `crds/` directory (NOT as
`templates/` rendered by `helm template`), so this component is delivered as **raw
vendored manifests** (`kind: manifests`) extracted once from the chart, not as a Helm
reference.

## What ships

Exactly 4 namespaced CustomResourceDefinitions in the `actions.github.com` API group,
each served at `v1alpha1`:

- `autoscalinglisteners.actions.github.com`
- `autoscalingrunnersets.actions.github.com`
- `ephemeralrunners.actions.github.com`
- `ephemeralrunnersets.actions.github.com`

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD schemas.
The `arc-system` and `arc-runners` Namespaces (with their Pod Security Admission
`enforce` labels) stay with the `automation/actions-runner-controller` workload
artifact.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the controller:

1. **`automation/actions-runner-controller-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting a CRD (and cascading the consumer's live `AutoscalingRunnerSet` /
     `EphemeralRunner` CRs, which would tear down registered runners) when the source
     removes it. The Helm-layer `helm.sh/resource-policy: keep` annotation is **not**
     honored by Argo for its own prune decisions, so `Prune=false` carries the
     guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit (the ARC CRDs carry large schemas) and is the convention for the strict-B
     `-crds` apps.

2. The workload Application **`automation/actions-runner-controller`** at sync-wave 0,
   which then comes up against CRDs that already exist (the `actions.github.com` API
   group is registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`automation/actions-runner-controller`.

## Regeneration / drift

The vendored manifest (`manifests/00-arc-crds.yaml`) was generated once from chart
`gha-runner-scale-set-controller` 0.14.2 via:

```sh
helm show crds \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.14.2 > manifests/00-arc-crds.yaml
```

The source chart+version (gha-runner-scale-set-controller 0.14.2) is the **drift
anchor**, and the 4-CRD set is pinned to it. A chart version bump requires
re-vendoring this file **and** an `automation/actions-runner-controller-crds` version
bump. It MUST be bumped **together** with the `automation/actions-runner-controller`
workload chart pin — the workload chart version and this vendored-CRD anchor are
coupled (both `gha-runner-scale-set-controller 0.14.2` today). The exact CRD count is
brittle on chart upgrade: **re-verify the 4-CRD set** when the chart version is bumped
(a future ARC release may add or remove a CRD). No mechanical drift check exists,
consistent with the `automation/velero-crds` precedent; the coupling is upheld by
convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the consumer's
Argo sync applies the new schema in-place (ServerSideApply). Because the consumer app
runs `Prune=false`, fields the upstream removes are **not** auto-pruned from the
cluster; removal needs manual intervention. A version bump is a separate reviewed
change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The `actions.github.com`
CRDs are the API surface (schemas), not a swappable operational capability. The
swappable capability `ci-runner` (self-hosted GitHub Actions runner infrastructure) is
provided by the workload artifact `automation/actions-runner-controller` (the
controller Deployment + RBAC that reconcile the `AutoscalingRunnerSet` /
`AutoscalingListener` / `EphemeralRunner` / `EphemeralRunnerSet` CRs), not by the CRD
schemas alone (precedent: `automation/velero-crds`, likewise api-surface-only with the
capability on its workload counterpart). The `provides[].api_surface` entries pin the
served surfaces — `actions.github.com/AutoscalingRunnerSet@v1alpha1` (the primary CRD
kind) through `actions.github.com/EphemeralRunnerSet@v1alpha1`.

## Sync-wave

`-1` — the CRDs land before the controller workload at wave 0, so the
`actions.github.com` API group is registered before the ARC controller starts
reconciling `AutoscalingRunnerSet` CRs.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/actions-runner-controller-crds:vX.Y.Z
```

The git tag is `automation/actions-runner-controller-crds-vX.Y.Z` (first release
`v0.1.0`); `task push` strips the leading `v`, so the OCI registry tag is the bare
SemVer. The workload `automation/actions-runner-controller` carries
`requires: {automation/actions-runner-controller-crds: ">=v0.1.0"}` — it renders zero
CRDs and depends on this artifact landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform layer model (OCI distribution)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

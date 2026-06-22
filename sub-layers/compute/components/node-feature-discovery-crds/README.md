# Component `compute/node-feature-discovery-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[Node Feature Discovery (NFD)](https://github.com/kubernetes-sigs/node-feature-discovery).
It ships **only** the 3 `nfd.k8s-sigs.io` `CustomResourceDefinition`s — the NFD
workload (master `Deployment` + worker `DaemonSet` + RBAC) is a **separate**
component, `compute/node-feature-discovery`. The two together form the strict-B
pair: CRDs first (this artifact, sync-wave -1), workload after (sync-wave 0).

The CRDs are vendored **verbatim** from the upstream chart
**node-feature-discovery 0.18.3** (appVersion `v0.18.3`,
`https://kubernetes-sigs.github.io/node-feature-discovery/charts`). The chart
ships the CRDs in its helm-native `crds/` directory (`crds/nfd-api-crds.yaml`), so
this component is delivered as a raw manifest (`kind: manifests`,
`manifests/00-nfd-crds.yaml`) — vendored **once** via
`helm pull node-feature-discovery --repo … --version 0.18.3 --untar`. The vendoring
is a one-time act, not the render path; a version bump re-vendors from the matching
chart.

## What ships

Exactly 3 resources, group `nfd.k8s-sigs.io`, all served+storage version
`v1alpha1`:

- `nodefeatures.nfd.k8s-sigs.io` (kind `NodeFeature`, scope `Namespaced`)
- `nodefeaturegroups.nfd.k8s-sigs.io` (kind `NodeFeatureGroup`, scope `Namespaced`)
- `nodefeaturerules.nfd.k8s-sigs.io` (kind `NodeFeatureRule`, scope `Cluster`)

No pods, no Services, no RBAC, no Namespace, no Deployment, no DaemonSet — the
artifact is purely the 3 CRDs. The NFD master/worker workloads,
`ClusterRole`/`ClusterRoleBinding`, and `ServiceAccount` from the upstream chart are
non-CRD objects and ship in the workload artifact
`compute/node-feature-discovery`, not here.

This artifact only establishes the CRD schemas so the NFD CRs have registered
types. The actual `NodeFeature`/`NodeFeatureRule`/`NodeFeatureGroup` CRs (the worker
produces `NodeFeature` objects; the operator and consumers author `NodeFeatureRule`
and `NodeFeatureGroup`) are runtime objects, not shipped here.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`compute/node-feature-discovery-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRDs (and cascading any live `NodeFeature`/`NodeFeatureRule`/
     `NodeFeatureGroup` CRs) when the source removes them. The Helm-layer
     `helm.sh/resource-policy: keep` is **not** honored by Argo for its own prune
     decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit and is the convention for the strict-B `-crds` apps.

2. The workload Application **`compute/node-feature-discovery`** at sync-wave 0,
   which then comes up against CRDs that already exist.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`compute/node-feature-discovery`.

## Upgrading the CRD schema

When this artifact is bumped to a newer NFD chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because the
consumer app runs `Prune=false`, fields the upstream removes are **not** auto-pruned
from the cluster; removal needs manual intervention. A version bump is a separate
reviewed change that re-vendors the CRDs from the matching upstream chart.

A safe schema-remove upgrade follows three steps:

1. Diff the live CRDs against the new artifact server-side before applying:
   `kubectl diff --server-side -f manifests/00-nfd-crds.yaml`.
2. For removed fields, apply the new schema explicitly with
   `kubectl apply --server-side --force-conflicts -f manifests/00-nfd-crds.yaml`
   (or `kubectl replace -f`) — this overwrites the field-owned schema in-place.
3. **Never** toggle `Prune=true` on the `-crds` Application while live NFD CRs
   exist: Argo would cascade-delete those CRs. Prune a removed CRD only after
   confirming no live CRs of that type remain.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The NFD CRDs are the API
surface (schemas), not a swappable operational capability. NFD labels and extends
nodes via its master/worker workload; it is not itself a swappable interface a
consumer would swap out independently of the workload, so neither the NFD workload
nor its CRDs carries a capability id. This is the deliberate no-capability design
state, not a deferral (precedent: `compute/kubevirt-cdi-crds` and
`observability/prometheus-operator-crds`, likewise api-surface-only).

## Sync-wave

`-1` — the CRDs land before the node-feature-discovery workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/node-feature-discovery-crds:vX.Y.Z
```

The git tag is `compute/node-feature-discovery-crds-vX.Y.Z`; `task push` strips the
leading `v`, so the OCI registry tag is the bare SemVer (the component name is the
OCI *path*, not the tag).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

# Component `compute/kubevirt-cdi-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the KubeVirt
[Containerized Data Importer (CDI)](https://github.com/kubevirt/containerized-data-importer).
It ships **only** the single `cdi.kubevirt.io` operator-config
`CustomResourceDefinition` — the operator workload is a **separate** component,
[`compute/kubevirt-cdi`](../kubevirt-cdi/README.md). The two together form the
strict-B pair: CRD first (this artifact, sync-wave -1), workload after
(sync-wave 0).

The CRD is sourced **verbatim** from the upstream CDI release operator manifest
at tag **v1.62.0**
(`https://github.com/kubevirt/containerized-data-importer/releases/download/v1.62.0/cdi-operator.yaml`,
vendored in `talos-platform-base` at
`kubernetes/base/infrastructure/kubevirt-cdi/cdi-operator.yaml`). CDI publishes no
anonymously-pullable CRDs-only Helm chart (the upstream install method is
`kubectl apply -f cdi-operator.yaml`), so this component is delivered as a raw
manifest (`kind: manifests`, `manifests/00-cdi-crds.yaml`) — the CRD object
extracted from the release manifest via
`yq -Y 'select(.kind == "CustomResourceDefinition")'`.

## What ships

Exactly one resource, group `cdi.kubevirt.io`, scope `Cluster`:

- `cdis.cdi.kubevirt.io` (kind `CDI`, served versions `v1beta1` and `v1alpha1`,
  storage version `v1beta1`)

No pods, no Services, no RBAC, no Namespace, no Deployment — the artifact is
purely the one CRD. The `Deployment` (`cdi-operator`),
`ClusterRole`/`ClusterRoleBinding`/`Role`/`RoleBinding`, and `ServiceAccount` from
the upstream operator manifest are non-CRD objects and ship in the workload
artifact `compute/kubevirt-cdi`, not here.

The `CDI` CR (the operator-config singleton, conventionally named `cdi` in the
`cdi` namespace) is shipped by the **workload** artifact `compute/kubevirt-cdi`
(at catalog defaults), not here. This artifact only establishes the CRD schema so
that CR has a registered type. The runtime CRDs (`datavolumes.cdi.kubevirt.io`,
`datasources.cdi.kubevirt.io`, `cdiconfigs.cdi.kubevirt.io`, …) are
**operator-installed at runtime** by `cdi-operator` once the `CDI` CR reconciles;
they are NOT in the operator manifest and are NOT shipped here (ADR-0028
"operator-installed CRDs — out of scope").

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`compute/kubevirt-cdi-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRD (and cascading the live `CDI` CR plus the operator-installed
     `DataVolume` CRs, which would tear down in-flight disk imports) when the source
     removes it. The Helm-layer `helm.sh/resource-policy: keep` is **not** honored
     by Argo for its own prune decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit (the CDI CRD schema is large) and is the convention for the strict-B
     `-crds` apps.

2. The workload Application **`compute/kubevirt-cdi`** at sync-wave 0, which then
   comes up against a CRD that already exists.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`compute/kubevirt-cdi`.

## Upgrading the CRD schema

When this artifact is bumped to a newer CDI release whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because
the consumer app runs `Prune=false`, fields the upstream removes are **not**
auto-pruned from the cluster; removal needs manual intervention. A version bump is
a separate reviewed change that re-extracts the CRD from the matching upstream
release.

A safe schema-remove upgrade follows three steps:

1. Diff the live CRD against the new artifact server-side before applying:
   `kubectl diff --server-side -f manifests/00-cdi-crds.yaml`.
2. For removed fields, apply the new schema explicitly with
   `kubectl apply --server-side --force-conflicts -f manifests/00-cdi-crds.yaml`
   (or `kubectl replace -f`) — this overwrites the field-owned schema in-place.
3. **Never** toggle `Prune=true` on the `-crds` Application while a live `CDI` CR
   (and its operator-installed `DataVolume` CRs) exists: Argo would cascade-delete
   those CRs and tear down in-flight disk imports. Prune a removed CRD only after
   confirming no live CRs of that type remain.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The CDI CRD is the API surface
(schema), not a swappable operational capability. CDI is a supporting
infrastructure component of the `vm-runtime` app (disk-image import for VMs); it is
not itself a swappable interface — no consumer would swap CDI out independently of
KubeVirt. This is the deliberate no-capability design state, not a deferral
(precedent: `storage-block/piraeus-operator-crds` and
`observability/prometheus-operator-crds`, likewise api-surface-only). The swappable
`vm-runtime` capability is provided by the KubeVirt workload artifact
`compute/kubevirt`.

## Sync-wave

`-1` — the CRD lands before the kubevirt-cdi workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/kubevirt-cdi-crds:vX.Y.Z
```

The git tag is `compute/kubevirt-cdi-crds-vX.Y.Z`; `task push` strips the leading
`v`, so the OCI registry tag is the bare SemVer (the component name is the OCI
*path*, not the tag).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

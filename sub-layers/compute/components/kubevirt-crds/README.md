# Component `compute/kubevirt-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[KubeVirt](https://github.com/kubevirt/kubevirt). It ships **only** the single
`kubevirt.io` operator-config `CustomResourceDefinition` — the operator workload is
a **separate** component, [`compute/kubevirt`](../kubevirt/README.md). The two
together form the strict-B pair: CRD first (this artifact, sync-wave -1), workload
after (sync-wave 0).

The CRD is sourced **verbatim** from the upstream KubeVirt release operator manifest
at tag **v1.5.0**
(`https://github.com/kubevirt/kubevirt/releases/download/v1.5.0/kubevirt-operator.yaml`).
KubeVirt publishes no anonymously-pullable CRDs-only Helm chart (the upstream install
method is `kubectl apply -f kubevirt-operator.yaml`), so this component is delivered
as a raw manifest (`kind: manifests`, `manifests/00-kubevirt-crds.yaml`) — the CRD
object extracted from the release manifest via
`yq 'select(.kind == "CustomResourceDefinition")'`.

## What ships

Exactly one resource, group `kubevirt.io`, scope `Namespaced`:

- `kubevirts.kubevirt.io` (kind `KubeVirt`, served versions `v1` and `v1alpha3`,
  storage version `v1`)

No pods, no Services, no RBAC, no Namespace, no PriorityClass, no webhook — the
artifact is purely the one CRD. The `Namespace`, `Deployment` (`virt-operator`),
`ClusterRole`/`ClusterRoleBinding`/`Role`/`RoleBinding`, `ServiceAccount`, and
`PriorityClass` from the upstream operator manifest are non-CRD objects and ship in
the workload artifact `compute/kubevirt`, not here.

The `KubeVirt` CR (the operator-config singleton, conventionally named `kubevirt` in
the `kubevirt` namespace) is **consumer-owned** — it lives in the consumer-cluster
repo overlay, not in this catalog component. This artifact only establishes the CRD
schema so that CR has a registered type. The runtime CRDs (`virtualmachines`,
`virtualmachineinstances`, …) are **operator-installed at runtime** by `virt-operator`
once the `KubeVirt` CR reconciles; they are NOT in the operator manifest and are NOT
shipped here (ADR-0028 "operator-installed CRDs — out of scope").

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`compute/kubevirt-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRD (and cascading the live `KubeVirt` CR plus the
     operator-installed `VirtualMachine` / `VirtualMachineInstance` CRs, which would
     tear down every running VM) when the source removes it. The Helm-layer
     `helm.sh/resource-policy: keep` is **not** honored by Argo for its own prune
     decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit (the KubeVirt CRD schema is large) and is the convention for the strict-B
     `-crds` apps.

2. The workload Application **`compute/kubevirt`** at sync-wave 0, which then comes up
   against a CRD that already exists.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`compute/kubevirt`.

## Upgrading the CRD schema

When this artifact is bumped to a newer KubeVirt release whose CRD schema changed,
the consumer's Argo sync applies the new schema in-place (ServerSideApply). Because
the consumer app runs `Prune=false`, fields the upstream removes are **not**
auto-pruned from the cluster; removal needs manual intervention. A version bump is a
separate reviewed change that re-extracts the CRD from the matching upstream release.

A safe schema-remove upgrade follows three steps:

1. Diff the live CRD against the new artifact server-side before applying:
   `kubectl diff --server-side -f manifests/00-kubevirt-crds.yaml`.
2. For removed fields, apply the new schema explicitly with
   `kubectl apply --server-side --force-conflicts -f manifests/00-kubevirt-crds.yaml`
   (or `kubectl replace -f`) — this overwrites the field-owned schema in-place.
3. **Never** toggle `Prune=true` on the `-crds` Application while a live `KubeVirt`
   CR (and its operator-installed VM CRs) exists: Argo would cascade-delete those CRs
   and tear down the running virtualization workloads. Prune a removed CRD only after
   confirming no live CRs of that type remain.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The KubeVirt CRD is the API
surface (schema), not a swappable operational capability. The swappable capability
(VM runtime) is provided by the workload artifact `compute/kubevirt` (the
`virt-operator` that reconciles the `KubeVirt` CR into the virtualization control
plane), not by the CRD schema alone (precedent:
`storage-block/piraeus-operator-crds` and `observability/prometheus-operator-crds`,
likewise api-surface-only).

## Sync-wave

`-1` — the CRD lands before the kubevirt workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/kubevirt-crds:vX.Y.Z
```

The git tag is `compute/kubevirt-crds-vX.Y.Z`; `task push` strips the leading `v`, so
the OCI registry tag is the bare SemVer (the component name is the OCI *path*, not the tag).

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

# Component `storage-objects/garage-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[garage](https://garagehq.deuxfleurs.fr/). It ships **only** the `GarageNode`
CustomResourceDefinition (`garagenodes.deuxfleurs.fr`) — the garage S3 workload is a
**separate** component, [`storage-objects/garage`](../garage/README.md). The two
together form the strict-B pair: CRD first (this artifact, sync-wave -1), workload
after (sync-wave 0).

The CRD is sourced **verbatim** from the upstream garage release **v2.3.0**
(`script/k8s/crd/` in the `deuxfleurs-org/garage` repository). Garage publishes no
dedicated CRDs-only Helm chart, so this component is delivered as a raw manifest
(`kind: manifests`, `manifests/00-garagenode-crd.yaml`).

## What ships

Exactly one resource:

- `garagenodes.deuxfleurs.fr`
  (group `deuxfleurs.fr`, version `v1`, kind `GarageNode`, scope `Namespaced`).

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD.

A consumer does not author `GarageNode` CRs by hand: garage's integrated Kubernetes
peer discovery creates and reconciles them at runtime (the workload's `ClusterRole`
carries the narrow `deuxfleurs.fr/garagenodes` grant for exactly that). This artifact
only establishes the CRD schema so those CRs have a registered type.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`storage-objects/garage-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRD (and cascading the live `GarageNode` CRs, which would break the
     garage cluster's peer discovery) when the source removes it. The Helm-layer
     `helm.sh/resource-policy: keep` is **not** honored by Argo for its own prune
     decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit and is the convention for the strict-B `-crds` apps.

2. The workload Application **`storage-objects/garage`** at sync-wave 0, which then
   comes up against a `GarageNode` CRD that already exists.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`storage-objects/garage`.

## Upgrading the CRD schema

When this artifact is bumped to a newer garage release whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because the
consumer app runs `Prune=false`, fields the upstream removes are **not** auto-pruned
from the cluster; removal needs manual intervention. A version bump is a separate
reviewed change.

## Capability

apis-only, **no capability** — `capabilities: []`. The `GarageNode` CRD is the API
surface (schema), not a swappable operational capability. The swappable capability
`s3-object` is provided by the workload artifact `storage-objects/garage` (the
StatefulSet that serves the S3 API), not by the CRD schema alone (precedent:
`network/multus-cni-crds`, likewise apis-only).

## Sync-wave

`-1` — the CRD lands before the garage workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage-crds:vX.Y.Z
```

The git tag is `storage-objects/garage-crds-vX.Y.Z`; `task push` strips the leading
`v`, so the OCI registry tag is the bare SemVer.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)

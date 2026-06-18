# Component `storage-block/piraeus-operator-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for the
[piraeus-operator](https://github.com/piraeusdatastore/piraeus-operator). It ships
**only** the four `piraeus.io` Linstor CustomResourceDefinitions — the operator
workload is a **separate** component,
[`storage-block/piraeus-operator`](../piraeus-operator/README.md). The two together
form the strict-B pair: CRDs first (this artifact, sync-wave -1), workload after
(sync-wave 0).

The CRDs are sourced **verbatim** from the upstream piraeus-operator release
`manifest.yaml` at tag **v2.10.7**
(`https://github.com/piraeusdatastore/piraeus-operator/releases/download/v2.10.7/manifest.yaml`).
piraeus-operator publishes no anonymously-pullable CRDs-only Helm chart (the
upstream install method is `kubectl apply --server-side -f manifest.yaml`), so this
component is delivered as a raw manifest (`kind: manifests`,
`manifests/00-linstor-crds.yaml`) — the four CRD objects extracted from the release
manifest via `yq 'select(.kind == "CustomResourceDefinition")'`.

## What ships

Exactly four resources, all group `piraeus.io`, served version `v1`, scope
`Cluster`:

- `linstorclusters.piraeus.io` (kind `LinstorCluster`)
- `linstornodeconnections.piraeus.io` (kind `LinstorNodeConnection`)
- `linstorsatelliteconfigurations.piraeus.io` (kind `LinstorSatelliteConfiguration`)
- `linstorsatellites.piraeus.io` (kind `LinstorSatellite`)

No pods, no Services, no RBAC, no Namespace, no webhook — the artifact is purely the
four CRDs. The Namespace, Deployments, RBAC, Service, and
ValidatingWebhookConfiguration from the upstream manifest are non-CRD objects and
ship in the workload artifact `storage-block/piraeus-operator`, not here.

Consumers author `LinstorCluster` and `LinstorSatelliteConfiguration` CRs against
these schemas to drive the operator. Those CRs are **consumer-owned** (they live in
the consumer-cluster repo overlay, not in this catalog component); this artifact only
establishes the CRD schemas so those CRs have a registered type.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the workload:

1. **`storage-block/piraeus-operator-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRDs (and cascading the live `LinstorCluster` / `LinstorSatellite`
     CRs, which would tear down the Linstor storage cluster) when the source removes
     them. The Helm-layer `helm.sh/resource-policy: keep` is **not** honored by Argo
     for its own prune decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit (the Linstor CRD schemas are large) and is the convention for the
     strict-B `-crds` apps.

2. The workload Application **`storage-block/piraeus-operator`** at sync-wave 0,
   which then comes up against CRDs that already exist.

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`storage-block/piraeus-operator`.

## Upgrading the CRD schema

When this artifact is bumped to a newer piraeus-operator release whose CRD schemas
changed, the consumer's Argo sync applies the new schema in-place
(ServerSideApply). Because the consumer app runs `Prune=false`, fields the upstream
removes are **not** auto-pruned from the cluster; removal needs manual intervention.
A version bump is a separate reviewed change.

A safe schema-remove upgrade follows three steps:

1. Diff the live CRDs against the new artifact server-side before applying:
   `kubectl diff --server-side -f manifests/00-linstor-crds.yaml`.
2. For removed fields, apply the new schema explicitly with
   `kubectl apply --server-side --force-conflicts -f manifests/00-linstor-crds.yaml`
   (or `kubectl replace -f`) — this overwrites the field-owned schema in-place.
3. **Never** toggle `Prune=true` on the `-crds` Application while live
   `LinstorCluster` / `LinstorSatellite` CRs exist: Argo would cascade-delete those
   CRs and tear down the Linstor storage cluster. Prune a removed CRD only after
   confirming no live CRs of that type remain.

## Capability

apis-only, **no capability** — `capabilities: []`. The four Linstor CRDs are the API
surface (schema), not a swappable operational capability. The swappable capability
`block-storage-replicated` is provided by the workload artifact
`storage-block/piraeus-operator` (the operator that reconciles these CRs into a
replicated DRBD/Linstor storage cluster), not by the CRD schemas alone (precedent:
`storage-objects/garage-crds` and `observability/prometheus-operator-crds`, likewise
apis-only).

## Sync-wave

`-1` — the CRDs land before the piraeus-operator workload at wave 0.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-block/piraeus-operator-crds:vX.Y.Z
```

The git tag is `storage-block/piraeus-operator-crds-vX.Y.Z`; `task push` strips the
leading `v`, so the OCI registry tag is the bare SemVer.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

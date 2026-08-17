---
type: reference
title: storage-objects sub-layer
description: Garage, an S3-compatible object store backing tf-state, iPXE images, LGTM-A, Velero, and app buckets.
tags: [reference, sub-layer, storage-objects]
timestamp: 2026-08-16
sources:
  - sub-layers/storage-objects/README.md
  - sub-layers/storage-objects/compatibility.yaml
---

# storage-objects sub-layer

Garage, an S3-compatible object store, backing Terraform state, iPXE images, the
LGTM-A backends, Velero, and application buckets. OCI prefix:
`ghcr.io/devobagmbh/talos-platform-apps/storage-objects/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| garage-crds | -1 | `-crds` half | - | - |
| garage-operator-crds | -1 | `-crds` half | - | secrets/cert-manager |
| garage | 0 | - | `s3-object` (drop-in) | storage-objects/garage-crds |
| garage-operator | 1 | workload half | `s3-bucket-provisioning` (rewrite-required) | storage-objects/garage-operator-crds, secrets/cert-manager |
| garage-buckets | 10 | - | - | storage-objects/garage, secrets/external-secrets |

## Notes

- `s3-object` is the capability the `observability` LGTM backends (`loki`/`mimir`/`tempo`) require.
- `garage-operator-crds` + `garage-operator` are the `rajsinghtech/garage-operator` adoption (#763, shape B: the operator becomes Garage's deployment mechanism and adds the declarative bucket/key provisioning path), an ADR-0028 strict-B pair from chart 0.7.3 that bumps in lockstep — a version skew between the CRD schemas and the controller breaks `GarageCluster` conversion. The two `GarageNode` kinds (`deuxfleurs.fr` from `garage-crds`, `garage.rajsingh.info` from this pair) coexist: different groups, no shortName collision, but the bare plural is group-ambiguous.
- `garage-operator` runs **namespace-scoped** (`watchNamespaces` set, so the chart renders a `Role`/`RoleBinding` per watched namespace instead of the manager `ClusterRole`/`ClusterRoleBinding`). As published it watches only its own namespace and holds **no cluster-wide access to any data object**; the only cluster-scoped rules it ships are `create` on `tokenreviews`/`subjectaccessreviews` for metrics authn, re-added in `manifests/10-metrics-rbac.yaml` because the chart gates its metrics RBAC on the cluster-wide mode. Consequences: `spec.storage.nodeLocalPools` and `spec.zoneFrom.nodeLabel` need cluster-scoped Node access and are therefore unavailable in the published shape; a consumer grants operand namespaces additively (`Role` + `RoleBinding` + a `--watch-namespaces` patch), and a CR in an unwatched namespace is admitted (the webhooks carry no `namespaceSelector`) but silently never reconciled. Within a watched namespace the operator still holds full `secrets` CRUD, and CR-create rights on `garageclusters`/`garagekeys` remain a privilege-escalation path a consumer must restrict.
- Migration of `garage` to an operator-owned `GarageCluster`, and the retirement of `garage-buckets`, are #763 follow-ups — the table above is the pre-migration state.
- `garage` carries a populated freeze-line (`config_files: /mnt/garage.toml` via `garage-config`; `secret_keys: rpcSecret`).
- Gaps (tracked in issue #523): `garage-buckets` lacks a `customization.yaml` and carries German README content; `garage-crds` carries a `FLAG: confirm` provenance marker.

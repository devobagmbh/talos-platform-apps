---
type: reference
title: storage-objects sub-layer
description: Garage, an S3-compatible object store backing tf-state, iPXE images, LGTM-A, Velero, and app buckets.
tags: [reference, sub-layer, storage-objects]
timestamp: 2026-08-14
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
- `garage-operator` holds a **cluster-wide `secrets` create/delete/get/list/patch/update/watch** grant plus cluster-wide node and workload write access, and a `GarageCluster` using `spec.storage.nodeLocalPools` makes it create hostPath DaemonSets (PSA `privileged` in the target namespace) — so CR-create rights on `garageclusters` are effectively a privilege-escalation path a consumer must restrict. Narrowing that grant to namespace scope is a **supported consumer overlay** (#795): the consumer drops the manager `ClusterRoleBinding` via `$patch: delete`, appends `--watch-namespaces`, and binds the shipped `ClusterRole` per namespace — at the cost of `nodes` and `storageclasses` access (so no `nodeLocalPools`, no `zoneFrom.nodeLabel`), and without mitigating per-namespace `secrets` CRUD or either CR-create escalation path. Because the consumer binds the role **by name**, `task validate:rbac-narrowing` pins its whole rule set against the committed `rbac-baseline.triples` golden, so an upstream bump cannot widen a narrowed consumer's grant — or falsify the documented cost — unreviewed. See DR-0004.
- Migration of `garage` to an operator-owned `GarageCluster`, and the retirement of `garage-buckets`, are #763 follow-ups — the table above is the pre-migration state.
- `garage` carries a populated freeze-line (`config_files: /mnt/garage.toml` via `garage-config`; `secret_keys: rpcSecret`).
- Gaps (tracked in issue #523): `garage-buckets` lacks a `customization.yaml` and carries German README content; `garage-crds` carries a `FLAG: confirm` provenance marker.

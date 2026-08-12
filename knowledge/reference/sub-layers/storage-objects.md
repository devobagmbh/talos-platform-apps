---
type: reference
title: storage-objects sub-layer
description: Garage, an S3-compatible object store backing tf-state, iPXE images, LGTM-A, Velero, and app buckets.
tags: [reference, sub-layer, storage-objects]
timestamp: 2026-08-12
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
| garage-buckets | 10 | - | - | storage-objects/garage, secrets/external-secrets |

## Notes

- `s3-object` is the capability the `observability` LGTM backends (`loki`/`mimir`/`tempo`) require.
- `garage-operator-crds` is the first half of the `rajsinghtech/garage-operator` adoption (#763, shape B: the operator becomes Garage's deployment mechanism and adds the declarative bucket/key provisioning path). Its controller half — `garage-operator`, sync-wave 1, providing `s3-bucket-provisioning` — follows in its own PR, and the two bump in lockstep. The two `GarageNode` kinds (`deuxfleurs.fr` from `garage-crds`, `garage.rajsingh.info` from this pair) coexist: different groups, no shortName collision, but the bare plural is group-ambiguous.
- Migration of `garage` to an operator-owned `GarageCluster`, and the retirement of `garage-buckets`, are #763 follow-ups — the table above is the pre-migration state.
- `garage` carries a populated freeze-line (`config_files: /mnt/garage.toml` via `garage-config`; `secret_keys: rpcSecret`).
- Gaps (tracked in issue #523): `garage-buckets` lacks a `customization.yaml` and carries German README content; `garage-crds` carries a `FLAG: confirm` provenance marker.

---
type: reference
title: storage-objects sub-layer
description: Garage, an S3-compatible object store backing tf-state, iPXE images, LGTM-A, Velero, and app buckets.
tags: [reference, sub-layer, storage-objects]
timestamp: 2026-07-11
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
| garage | 0 | - | `s3-object` (drop-in) | storage-objects/garage-crds |
| garage-buckets | 10 | - | - | storage-objects/garage, secrets/external-secrets |

## Notes

- `s3-object` is the capability the `observability` LGTM backends (`loki`/`mimir`/`tempo`) require.
- `garage` carries a populated freeze-line (`config_files: /mnt/garage.toml` via `garage-config`; `secret_keys: rpcSecret`).
- Gaps ([gap analysis](../../gap-analysis.md)): `garage-buckets` lacks a `customization.yaml` and carries German README content; `garage-crds` carries a `FLAG: confirm` provenance marker.

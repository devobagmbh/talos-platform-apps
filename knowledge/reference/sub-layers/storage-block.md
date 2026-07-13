---
type: reference
title: storage-block sub-layer
description: Block-storage CSI drivers exposing block PersistentVolumes.
tags: [reference, sub-layer, storage-block]
timestamp: 2026-07-13
sources:
  - sub-layers/storage-block/README.md
  - sub-layers/storage-block/compatibility.yaml
---

# storage-block sub-layer

Block-storage CSI drivers exposing block PersistentVolumes. OCI prefix:
`ghcr.io/devobagmbh/talos-platform-apps/storage-block/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| piraeus-operator-crds | -1 | `-crds` half | - | - |
| snapshot-controller-crds | -1 | `-crds` half | - | - |
| piraeus-operator | 0 | - | `block-storage-replicated` (data-migration) | storage-block/piraeus-operator-crds |
| snapshot-controller | 0 | - | - | storage-block/snapshot-controller-crds |
| democratic-csi | 0 | - | `block-storage-network` (data-migration) | - |
| synology-csi | 0 | - | `block-storage-network` (data-migration) | - |
| local-path-provisioner | 0 | - | `block-storage-local` (data-migration) | - |

## Notes

- strict-B `-crds` halves: `piraeus-operator-crds`, `snapshot-controller-crds`.
- `democratic-csi` and `synology-csi` carry populated freeze-lines (driver-config secrets).
- Gaps (tracked in issue #523): `synology-csi` is documented as deprecated / non-functional on Talos (chroot `/host`, superseded by `democratic-csi`) yet still ships. (The former "undefined block-storage capability" gap is resolved — `block-storage-network` is now defined in `catalog/capability-index.yaml` and wired onto both `democratic-csi` and `synology-csi` via #538/#539.)

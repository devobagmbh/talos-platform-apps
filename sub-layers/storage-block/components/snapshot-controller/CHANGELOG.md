# Changelog

## Unreleased

### Features

* **storage-block/snapshot-controller:** initial component — the workload half
  (ADR-0028 strict-B) of the snapshot-controller pair, shipping the cluster-singleton
  external-snapshotter v8.5.0 snapshot-controller Deployment + its cluster-scoped
  RBAC + a dedicated PSA-`restricted` Namespace via the piraeus.io
  `snapshot-controller` chart 5.0.4 (`installCRDs: false`, leader-election enabled,
  conversion webhook disabled). The six CRDs ship in the sibling
  `storage-block/snapshot-controller-crds` (sync-wave -1).

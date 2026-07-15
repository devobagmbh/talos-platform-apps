# Changelog

## [0.1.1](https://github.com/devobagmbh/talos-platform-apps/compare/storage-block/snapshot-controller-v0.1.0...storage-block/snapshot-controller-v0.1.1) (2026-07-15)


### Bug Fixes

* **storage-block/snapshot-controller:** migrate to native-OCI Kustomize base ([#594](https://github.com/devobagmbh/talos-platform-apps/issues/594)) ([a736a52](https://github.com/devobagmbh/talos-platform-apps/commit/a736a52e8ec9d7ce7a7836b9782305426b60aadc))

## 0.1.0 (2026-06-25)


### Features

* **storage-block/snapshot-controller:** external-snapshotter workload (strict-B) ([92f0cfe](https://github.com/devobagmbh/talos-platform-apps/commit/92f0cfe78711143c6b923b911dee883d2c35cd80))

## Changelog

## Unreleased

### Features

* **storage-block/snapshot-controller:** initial component — the workload half
  (ADR-0028 strict-B) of the snapshot-controller pair, shipping the cluster-singleton
  external-snapshotter v8.5.0 snapshot-controller Deployment + its cluster-scoped
  RBAC + a dedicated PSA-`restricted` Namespace via the piraeus.io
  `snapshot-controller` chart 5.0.4 (`installCRDs: false`, leader-election enabled,
  conversion webhook disabled). The six CRDs ship in the sibling
  `storage-block/snapshot-controller-crds` (sync-wave -1).

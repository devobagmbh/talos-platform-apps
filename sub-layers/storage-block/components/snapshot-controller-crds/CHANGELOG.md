# Changelog

## [0.1.1](https://github.com/devobagmbh/talos-platform-apps/compare/storage-block/snapshot-controller-crds-v0.1.0...storage-block/snapshot-controller-crds-v0.1.1) (2026-07-15)


### Bug Fixes

* **storage-block/snapshot-controller-crds:** migrate to native-OCI Kustomize base ([#592](https://github.com/devobagmbh/talos-platform-apps/issues/592)) ([a8a2974](https://github.com/devobagmbh/talos-platform-apps/commit/a8a29742f5101ce910b72909a9b0635644b08d07))

## 0.1.0 (2026-06-25)


### Features

* **storage-block/snapshot-controller-crds:** external-snapshotter CRDs (strict-B CRD half) ([#361](https://github.com/devobagmbh/talos-platform-apps/issues/361)) ([b64f5fb](https://github.com/devobagmbh/talos-platform-apps/commit/b64f5fbc11aa01b42448911f0c1516383b6eb12d))

## Changelog

## Unreleased

### Features

* **storage-block/snapshot-controller-crds:** initial component — the strict-B
  CRDs artifact (ADR-0028) for the snapshot-controller, shipping the six
  external-snapshotter v8.5.0 CustomResourceDefinitions (the
  `snapshot.storage.k8s.io` and `groupsnapshot.storage.k8s.io` API groups) via the
  piraeus.io `snapshot-controller` chart 5.0.4.

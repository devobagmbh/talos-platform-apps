# Changelog

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

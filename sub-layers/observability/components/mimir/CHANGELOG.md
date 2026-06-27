# Changelog

## [0.3.0](https://github.com/devobagmbh/talos-platform-apps/compare/observability/mimir-v0.2.1...observability/mimir-v0.3.0) (2026-06-27)


### Features

* **observability/mimir:** raise per-tenant ingestion limits ([#411](https://github.com/devobagmbh/talos-platform-apps/issues/411)) ([4b526fa](https://github.com/devobagmbh/talos-platform-apps/commit/4b526fa765df918259ba354917033eb742eb89f2)), closes [#410](https://github.com/devobagmbh/talos-platform-apps/issues/410)


### Bug Fixes

* **observability/mimir:** make ruler.alertmanager_url consumer-overridable ([#403](https://github.com/devobagmbh/talos-platform-apps/issues/403)) ([bc9c440](https://github.com/devobagmbh/talos-platform-apps/commit/bc9c4402696c678aa538b7cd45f4992f2f54ab37)), closes [#402](https://github.com/devobagmbh/talos-platform-apps/issues/402)

## [0.2.1](https://github.com/devobagmbh/talos-platform-apps/compare/observability/mimir-v0.2.0...observability/mimir-v0.2.1) (2026-06-25)


### Bug Fixes

* **observability/mimir:** set replication_factor 1 for single-replica footprint ([#380](https://github.com/devobagmbh/talos-platform-apps/issues/380)) ([64b9920](https://github.com/devobagmbh/talos-platform-apps/commit/64b992028c767996ced8feadb2f99c2b3bfaf9aa)), closes [#379](https://github.com/devobagmbh/talos-platform-apps/issues/379)

## [0.2.0](https://github.com/devobagmbh/talos-platform-apps/compare/observability/mimir-v0.1.0...observability/mimir-v0.2.0) (2026-06-25)


### Features

* **catalog:** enforce compatibility.yaml schema + migrate docs/primitives to the version: block ([#246](https://github.com/devobagmbh/talos-platform-apps/issues/246)) ([ccffb09](https://github.com/devobagmbh/talos-platform-apps/commit/ccffb096b67e5b6129afb213dffae6eaba281bec))
* **catalog:** migrate 9 unbuilt stub compatibility.yaml to api_surface (issue [#246](https://github.com/devobagmbh/talos-platform-apps/issues/246) Part B) ([1dd5f65](https://github.com/devobagmbh/talos-platform-apps/commit/1dd5f6590669eab9c5095a50ac2a12646e13b164))
* **observability/mimir:** add Grafana Mimir metrics-store catalog component ([#326](https://github.com/devobagmbh/talos-platform-apps/issues/326)) ([bc9a44e](https://github.com/devobagmbh/talos-platform-apps/commit/bc9a44e2dfddd9d0f999f36bf9f69823a375fb44))

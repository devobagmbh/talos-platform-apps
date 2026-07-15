# Changelog

## [0.1.2](https://github.com/devobagmbh/talos-platform-apps/compare/observability/loki-v0.1.1...observability/loki-v0.1.2) (2026-07-15)


### Bug Fixes

* **observability/loki:** migrate to native-OCI Kustomize base ([#568](https://github.com/devobagmbh/talos-platform-apps/issues/568)) ([e067ac4](https://github.com/devobagmbh/talos-platform-apps/commit/e067ac40de93c9a3796b86b192f8036eb47a838a))

## [0.1.1](https://github.com/devobagmbh/talos-platform-apps/compare/observability/loki-v0.1.0...observability/loki-v0.1.1) (2026-06-25)


### Bug Fixes

* **observability/loki:** clarify S3_INSECURE is a required key ([#377](https://github.com/devobagmbh/talos-platform-apps/issues/377)) ([063375e](https://github.com/devobagmbh/talos-platform-apps/commit/063375e6f2b9ba3eae6ce166da68e2b1abf10dc9))

## 0.1.0 (2026-06-24)


### Features

* **catalog:** enforce compatibility.yaml schema + migrate docs/primitives to the version: block ([#246](https://github.com/devobagmbh/talos-platform-apps/issues/246)) ([ccffb09](https://github.com/devobagmbh/talos-platform-apps/commit/ccffb096b67e5b6129afb213dffae6eaba281bec))
* **catalog:** migrate 9 unbuilt stub compatibility.yaml to api_surface (issue [#246](https://github.com/devobagmbh/talos-platform-apps/issues/246) Part B) ([1dd5f65](https://github.com/devobagmbh/talos-platform-apps/commit/1dd5f6590669eab9c5095a50ac2a12646e13b164))
* **observability/loki:** add Grafana Loki SingleBinary catalog component ([#322](https://github.com/devobagmbh/talos-platform-apps/issues/322)) ([ccb935c](https://github.com/devobagmbh/talos-platform-apps/commit/ccb935ca030f02987a07d4ed20ccd1004fde0f5f))


### Bug Fixes

* **observability/loki:** make S3 endpoint TLS (insecure) consumer-optional ([#360](https://github.com/devobagmbh/talos-platform-apps/issues/360)) ([7deae36](https://github.com/devobagmbh/talos-platform-apps/commit/7deae36d5d4daf049dee9f5c053c6a2516d2aa3e)), closes [#359](https://github.com/devobagmbh/talos-platform-apps/issues/359)

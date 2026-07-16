# Changelog

## [0.1.1](https://github.com/devobagmbh/talos-platform-apps/compare/secrets/external-secrets-crds-v0.1.0...secrets/external-secrets-crds-v0.1.1) (2026-07-15)


### Bug Fixes

* **secrets/external-secrets-crds:** migrate to native-OCI Kustomize base ([#584](https://github.com/devobagmbh/talos-platform-apps/issues/584)) ([a12c6e5](https://github.com/devobagmbh/talos-platform-apps/commit/a12c6e55c6eca673aa563789c74f2b85fa93b5fe))

## 0.1.0 (2026-06-23)


### ⚠ BREAKING CHANGES

* **secrets/external-secrets:** the single `external-secrets` Argo Application becomes two — `secrets/external-secrets-crds` at sync-wave -1 (Prune=false,ServerSideApply=true) plus `secrets/external-secrets` at sync-wave 0. Consumers MUST deploy both apps; the workload now requires `secrets/external-secrets-crds`, and the GithubAccessToken generator CRD (ADR-0025) lives in the -crds half.

### Code Refactoring

* **secrets/external-secrets:** migrate to strict-B CRD split (ADR-0028) ([#329](https://github.com/devobagmbh/talos-platform-apps/issues/329)) ([8d2674a](https://github.com/devobagmbh/talos-platform-apps/commit/8d2674a8a26b4e2f727f992d178d62fafa09b99c))

## Changelog

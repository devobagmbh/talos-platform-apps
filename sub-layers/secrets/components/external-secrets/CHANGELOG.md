# Changelog

## Unreleased

### ⚠ BREAKING CHANGES

* **secrets/external-secrets:** migrate to the strict-B CRD split (ADR-0028). The
  CRDs are removed from this workload (`installCRDs: false` → renders 0
  `CustomResourceDefinition`) and now ship in the separate
  `secrets/external-secrets-crds` artifact. The single `external-secrets` Argo
  `Application` becomes **two**: `secrets/external-secrets-crds` at sync-wave -1
  (`Prune=false,ServerSideApply=true`) and `secrets/external-secrets` at
  sync-wave 0. Consumers MUST deploy **both** apps — the operator now `requires`
  `secrets/external-secrets-crds`, and the `GithubAccessToken` generator CRD
  (ADR-0025) lives in the `-crds` half. ([#201](https://github.com/devobagmbh/talos-platform-apps/issues/201))

## [1.0.0](https://github.com/devobagmbh/talos-platform-apps/compare/secrets/external-secrets-v0.2.0...secrets/external-secrets-v1.0.0) (2026-06-23)


### ⚠ BREAKING CHANGES

* **secrets/external-secrets:** the single `external-secrets` Argo Application becomes two — `secrets/external-secrets-crds` at sync-wave -1 (Prune=false,ServerSideApply=true) plus `secrets/external-secrets` at sync-wave 0. Consumers MUST deploy both apps; the workload now requires `secrets/external-secrets-crds`, and the GithubAccessToken generator CRD (ADR-0025) lives in the -crds half.

### Code Refactoring

* **secrets/external-secrets:** migrate to strict-B CRD split (ADR-0028) ([#329](https://github.com/devobagmbh/talos-platform-apps/issues/329)) ([8d2674a](https://github.com/devobagmbh/talos-platform-apps/commit/8d2674a8a26b4e2f727f992d178d62fafa09b99c))

## [0.2.0](https://github.com/devobagmbh/talos-platform-apps/compare/secrets/external-secrets-v0.1.0...secrets/external-secrets-v0.2.0) (2026-06-21)


### Features

* **catalog:** version provenance — typed version block + A7 parity gate ([#226](https://github.com/devobagmbh/talos-platform-apps/issues/226)) ([cfee128](https://github.com/devobagmbh/talos-platform-apps/commit/cfee128799403598d9f28a596f4d2271e7167ffb))

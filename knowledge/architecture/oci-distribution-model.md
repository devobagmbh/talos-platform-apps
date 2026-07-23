---
type: architecture
title: OCI distribution model
description: The component as the OCI distribution unit, directory == identity, and the tag / path scheme.
tags: [architecture, oci, versioning]
timestamp: 2026-07-23
sources:
  - AGENTS.md
  - Taskfile.yml
---

# OCI distribution model

Authoritative source: `AGENTS.md` (§Repository Purpose, §Coding Style,
§Hard Constraints) and `talos-platform-docs/adr/0009-platform-layer-model.md`.

The OCI distribution unit is the **component**. The sub-layer is only an
organizational directory grouping. Within each sub-layer, one or more components
live as independently versioned OCI artifacts.

## Identity is the directory

- `sub-layers/<sub-layer>/components/<component>/` produces the OCI path `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>/<component>`.
- The git-tag pattern is `<sub-layer>/<component>-vMAJ.MIN.PATCH` (SemVer, independent lifecycle per component).
- The OCI org path is hard-coded; renaming it requires coordination with all consumers (a Hard Constraint).

## Build to artifact

The pipeline is render -> package -> push -> sign, all through `task` targets
(see [CI and merge gates](../reference/ci-and-merge-gates.md) for the CI
conventions that bind this):

- `task render:one -- <sub-layer>/<component>` - `helm template` + manifest concatenation into the gitignored `rendered/`.
- `task push` - native OCI push (single-layer manifest tarball) via `oras`.
- `task sign` - keyless `cosign` signing with the GHA OIDC workflow identity.
- `task publish` - render -> package -> push -> sign in one step.

## Signing identity

cosign signing is keyless with GHA OIDC: the signing identity **is** the
workflow identity (`oci-publish.yml@refs/tags/...`). No long-lived keys are ever
committed. This identity is what the consumer-side Kyverno policy and `task verify`
check against.

## Where the detail lives

- OCI granularity and the "component is the unit" decision: `talos-platform-docs/adr/0009-platform-layer-model.md`.
- The task surface: `AGENTS.md` §Build, Test, Development Commands and `Taskfile.yml`.
- The strict-B CRD-split exception to "one artifact per component": [CRD management (strict-B)](crd-management-strict-b.md).

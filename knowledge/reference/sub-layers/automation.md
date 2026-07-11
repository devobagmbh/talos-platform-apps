---
type: reference
title: automation sub-layer
description: Cluster backup (Velero) and dependency-update automation.
tags: [reference, sub-layer, automation]
timestamp: 2026-07-11
sources:
  - sub-layers/automation/README.md
  - sub-layers/automation/compatibility.yaml
---

# automation sub-layer

Cluster backup (Velero) plus GitHub Actions self-hosted runners. OCI prefix:
`ghcr.io/devobagmbh/talos-platform-apps/automation/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| actions-runner-controller-crds | -1 | `-crds` half | - | - |
| actions-runner-controller | 0 | - | `ci-runner` (rewrite-required) | automation/actions-runner-controller-crds |
| velero-crds | -1 | `-crds` half | - | - |
| velero | 0 | - | (TODO `backup`) | - |

## Notes

- strict-B `-crds` halves: `actions-runner-controller-crds`, `velero-crds` (sync-wave -1, `Prune=false`).
- Gaps (tracked in issue #523): `velero` lacks `customization.yaml` and declares `capabilities: []` with a `backup`-capability TODO; `ci-runner` is a contract-open capability.

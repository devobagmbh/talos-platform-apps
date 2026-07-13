---
type: reference
title: security sub-layer
description: Multi-tenancy/governance (Capsule) and runtime security (Tetragon).
tags: [reference, sub-layer, security]
timestamp: 2026-07-11
sources:
  - sub-layers/security/README.md
  - sub-layers/security/compatibility.yaml
---

# security sub-layer

Multi-tenancy / governance and runtime security tooling for consumer clusters.
OCI prefix: `ghcr.io/devobagmbh/talos-platform-apps/security/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| capsule-crds | -1 | `-crds` half | - | - |
| capsule | 0 | - | `namespace-tenancy` (rewrite-required) | security/capsule-crds |
| tetragon | 0 | - | `runtime-security` (rewrite-required) | - |

## Notes

- strict-B `-crds` half: `capsule-crds`.
- `tetragon` declares `provided_selectors` (the label sets consumer `TracingPolicy` / `TracingPolicyNamespaced` CRs must carry) rather than a `required.*` freeze-line.

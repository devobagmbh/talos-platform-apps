---
type: reference
title: compute sub-layer
description: VM runtime (KubeVirt + CDI), GPU scheduling, and hardware-feature detection.
tags: [reference, sub-layer, compute]
timestamp: 2026-07-11
sources:
  - sub-layers/compute/README.md
  - sub-layers/compute/compatibility.yaml
---

# compute sub-layer

VM runtime, GPU scheduling, and hardware-feature detection — capability-first.
OCI prefix: `ghcr.io/devobagmbh/talos-platform-apps/compute/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| kubevirt-crds | -1 | `-crds` half | - | - |
| kubevirt | 0 | - | `vm-runtime` (rewrite-required) | compute/kubevirt-crds |
| kubevirt-cdi-crds | -1 | `-crds` half | - | - |
| kubevirt-cdi | 0 | - | - | compute/kubevirt-cdi-crds |
| node-feature-discovery-crds | -1 | `-crds` half | - | - |
| node-feature-discovery | 0 | - | - | compute/node-feature-discovery-crds |
| nvidia-device-plugin | 1 | - | `gpu-runtime` (rewrite-required) | compute/node-feature-discovery |

## Notes

- strict-B `-crds` halves: `kubevirt-crds`, `kubevirt-cdi-crds`, `node-feature-discovery-crds`.
- `nvidia-device-plugin` runs at sync-wave 1 (after node-feature-discovery labels nodes).

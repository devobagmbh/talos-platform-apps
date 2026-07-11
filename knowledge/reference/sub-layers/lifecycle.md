---
type: reference
title: lifecycle sub-layer
description: Crossplane, its providers/compositions, and iPXE for child-cluster provisioning.
tags: [reference, sub-layer, lifecycle]
timestamp: 2026-07-11
sources:
  - sub-layers/lifecycle/README.md
  - sub-layers/lifecycle/compatibility.yaml
---

# lifecycle sub-layer

Crossplane plus its providers and compositions, and iPXE for stage-1 bare-metal
provisioning. OCI prefix: `ghcr.io/devobagmbh/talos-platform-apps/lifecycle/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities / provides | Requires |
|---|---|---|---|---|
| crossplane | 0 | - | `cluster-provisioning` (rewrite-required) | - |
| ipxe | 0 | - | provides `ipxe-server` (TODO `bare-metal-boot`) | - |
| booter | 0 | - | `bare-metal-boot` (role proxydhcp) | - |
| providers | 10 | - | 4 Crossplane packages (opentofu, kubernetes, patch-and-transform, auto-ready) | lifecycle/crossplane |
| compositions | 20 | - | provides `xcluster-api`; `cluster-provisioning` (rewrite-required) | lifecycle/crossplane, lifecycle/providers |
| crossview | 30 | - | - | lifecycle/crossplane, `cnpg-postgres` (cap) |

## Sync-wave order

Crossplane (0) → providers (10) → compositions (20) → crossview (30): each stage
depends on the operators/packages the previous one installs.

## Notes

- Gaps ([gap analysis](../../gap-analysis.md)): `bare-metal-boot` is wired inconsistently across `booter` (declares it, no `swap_class`) and `ipxe` (`capabilities: []` + TODO); `booter` and `ipxe` lack a `customization.yaml`/have a `sot: none` respectively; relocation of `ipxe` out of the catalog is tracked upstream.
- `crossview` and `ipxe` carry populated freeze-lines (consumer secrets / boot-script config).

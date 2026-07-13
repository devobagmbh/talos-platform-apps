---
type: reference
title: network sub-layer
description: Secondary networking (Multus) and NTP (chrony) add-ons; the primary CNI is base's Cilium.
tags: [reference, sub-layer, network]
timestamp: 2026-07-11
sources:
  - sub-layers/network/README.md
  - sub-layers/network/compatibility.yaml
---

# network sub-layer

Network add-ons for the catalog; the primary CNI (Cilium) is substrate, in
`talos-platform-base`. OCI prefix: `ghcr.io/devobagmbh/talos-platform-apps/network/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| multus-cni-crds | -1 | `-crds` half | - | - |
| multus-cni | 0 | - | `secondary-network-attachment` (rewrite-required) | network/multus-cni-crds |
| chrony | 0 | - | `ntp-service` (consumer-change) | - |

## Notes

- `chrony` carries a freeze-line (`config_files: /etc/chrony.conf` via `chrony-config`) and declares an `exposed_selectors.lb_ipam` binding surface (a consumer LB-IPAM pool selects the service by label without patching the signed Service).
- strict-B `-crds` half: `multus-cni-crds`.

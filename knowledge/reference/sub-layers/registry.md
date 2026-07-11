---
type: reference
title: registry sub-layer
description: Harbor as the container/OCI registry with a pull-through cache.
tags: [reference, sub-layer, registry]
timestamp: 2026-07-11
sources:
  - sub-layers/registry/README.md
  - sub-layers/registry/compatibility.yaml
---

# registry sub-layer

Harbor as the container/OCI registry with a pull-through cache. OCI prefix:
`ghcr.io/devobagmbh/talos-platform-apps/registry/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| harbor | 0 | - | (TODO `oci-registry`) | `cnpg-postgres` (cap), `redis-managed` (cap) |

## Notes

- `harbor` composes the `databases` sub-layer's capabilities: it requires `cnpg-postgres` (PostgreSQL) and `redis-managed` (Valkey) rather than shipping its own.
- It carries a freeze-line (`secret_keys: HARBOR_ADMIN_PASSWORD, secretKey`).
- Gap (tracked in issue #523): ships with `capabilities: []` and an `oci-registry` capability TODO (contract open).

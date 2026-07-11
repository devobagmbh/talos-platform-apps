---
type: reference
title: databases sub-layer
description: Managed PostgreSQL (CloudNativePG) and Valkey (redis-managed).
tags: [reference, sub-layer, databases]
timestamp: 2026-07-11
sources:
  - sub-layers/databases/README.md
  - sub-layers/databases/compatibility.yaml
---

# databases sub-layer

Managed PostgreSQL via CloudNativePG and a Valkey operator. OCI prefix:
`ghcr.io/devobagmbh/talos-platform-apps/databases/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| cnpg-crds | -1 | `-crds` half | - | - |
| cnpg | 0 | - | `cnpg-postgres` (data-migration) | databases/cnpg-crds |
| valkey-operator | 0 | - | `redis-managed` (data-migration) | - |

## Notes

- `cnpg-postgres` and `redis-managed` are capabilities other components consume by id (e.g. `registry/harbor` requires both; `lifecycle/crossview` requires `cnpg-postgres`).
- strict-B `-crds` half: `cnpg-crds`.

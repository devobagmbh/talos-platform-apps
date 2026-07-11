---
type: reference
title: identity sub-layer
description: Cluster identity via an OIDC broker (Dex) federating an upstream IdP.
tags: [reference, sub-layer, identity]
timestamp: 2026-07-11
sources:
  - sub-layers/identity/README.md
  - sub-layers/identity/compatibility.yaml
---

# identity sub-layer

Cluster identity — an OIDC broker (Dex) federating an upstream identity provider.
OCI prefix: `ghcr.io/devobagmbh/talos-platform-apps/identity/`.

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| dex | 0 | - | `identity-oidc` | - |

## Notes

- `dex` carries a freeze-line with consumer input: `secret_keys: [config.yaml]` via `provided_refs.secret = dex-config`.
- Gap (tracked in issue #523): the `identity-oidc` capability is declared without a `swap_class` (older contract shape).

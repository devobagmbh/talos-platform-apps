---
type: architecture
title: Capability-layer model
description: Capability as the stable interface a consumer composes against, tool as the swappable implementation, with swap-class quantifying swap cost.
tags: [architecture, capability, swap-class]
timestamp: 2026-07-23
sources:
  - catalog/capability-index.yaml
  - catalog/README.md
  - schemas/compatibility.schema.json
  - AGENTS.md
---

# Capability-layer model

Authoritative source: `catalog/capability-index.yaml` (the registry),
`catalog/README.md` (the swap-class semantics), and
`talos-platform-docs/adr/0021-capability-layer-model.md`.

A **capability** is the stable interface a consumer composes against; the
**tool** implementing it is swappable. `catalog/capability-index.yaml` is the
central registry: each entry has a stable `id`, a `domain`, and one or more
`implementations` with a status and a `swap_class`.

## swap_class

`swap_class` quantifies the cost of swapping one implementation for another:

- `drop-in` - same contract, no data move (consumer-invisible).
- `label-move` - swap is a label move on the producer pod (consumer-invisible).
- `data-migration` - swap requires a data move.
- `rewrite-required` - tool-specific CRs must be rewritten.
- `consumer-change` - the consumer must adjust its reference.

## How a component declares against it

In a component's `compatibility.yaml` (see [Component contract](../reference/component-contract.md)):

- `requires` names catalog-internal component dependencies **and** capability ids (bare id from the index).
- `provides[].capabilities[]` additively lists the capabilities a component implements, each `{id, swap_class}`; every `id` must exist in the index.
- A component with no matching capability carries `capabilities: []`; a `-crds` strict-B half carries `[]` permanently.

## Where the detail lives

- Registry + full entry shape: `catalog/capability-index.yaml` and `catalog/README.md`.
- Model rationale (three-layer capability model): `talos-platform-docs/adr/0021-capability-layer-model.md`.
- The `provides` / `requires` schema: `schemas/compatibility.schema.json`.

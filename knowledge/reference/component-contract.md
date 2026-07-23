---
type: reference
title: Component contract
description: The two per-component contract files - compatibility.yaml (dependency + capability surface) and customization.yaml (the freeze-line).
tags: [reference, contract, freeze-line, compatibility]
timestamp: 2026-07-23
sources:
  - schemas/compatibility.schema.json
  - schemas/customization.schema.json
  - AGENTS.md
---

# Component contract

Every component carries two schema-validated contract files that ship inside the
OCI artifact. Authoritative source: the schema descriptions in
`schemas/compatibility.schema.json` and `schemas/customization.schema.json`, and
`AGENTS.md` §Sub-layer and component conventions.

## compatibility.yaml - dependency + capability surface

Declares what the component needs and what it offers:

- `requires` - catalog-internal component dependencies (`<sub-layer>/<component>: ">=vX.Y.Z"`) **and** capability ids (bare id from `catalog/capability-index.yaml`). No `talos-platform-base` line (apps does not depend on base).
- `provides[]` - each entry names what it ships (`name:`, mandatory) and additively lists `capabilities[]` (`{id, swap_class}`) and `api_surface[]` (CRD/API groups exposed).
- `crd-bearing` - the marker that drives the strict-B split (see [CRD management](../architecture/crd-management-strict-b.md)).

Validated for structural shape by `task validate:compatibility`; `provides[]`
items are a closed set (`additionalProperties: false`) - a legacy `apis` key
fails validation by design.

## customization.yaml - the freeze-line (ADR-0024 v2)

Declares the workload/config boundary and the four config shapes a pre-rendered
OCI component expects from the consumer. Required keys: `freeze_line`,
`provided_refs`, `provided_selectors`, `required`, `sync_wave`,
`external_dependencies`.

- `freeze_line.workload` - path to the pre-rendered, signed workload baseline. The **image digest is the hard consumer-admission anchor** (cosign verifyImages); most other fields are consumer-overlayable per-cluster, except platform-set fields like `sync_wave` and dangerous classes (hostPath, cluster-admin bindings) that consumer-side Kyverno safe-defaults discourage.
- `provided_refs` / `required` - the consumer-input surface across four shapes: (a) env ConfigMap via `envFrom`, (b) mounted config file, (c) runtime Secret, (d) operator-assembled config via labelled CRs. Empty for cluster-agnostic components.
- `sync_wave` - the ArgoCD sync-wave, pre-rendered as a platform property (string matching `^-?[0-9]+$`); the consumer does not patch it.
- `external_dependencies` - other components (`<sub-layer>/<component>`) that must exist in the cluster first.

Validated for structural shape by `task validate:contract`. Note: this schema is
structural typing only - freeze-line **semantics** (each `required.*` entry
maps to a real rendered ref) is not gated at rest; see [DR-0001](../decisions/DR-0001-specification-driven-component-build.md) §D3.

## Where the detail lives

- Field-by-field semantics: the `description` strings in `schemas/*.schema.json`.
- The freeze-line design (calibrated-friction, image-as-anchor): `talos-platform-docs/adr/0024`.
- The schema-contract-parity decisions for each schema: the schema `description` headers.

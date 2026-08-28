---
type: reference
title: Component contract
description: The two per-component contract files - compatibility.yaml (dependency + capability surface) and customization.yaml (the freeze-line, with the required and optional consumer-input channels).
tags: [reference, contract, freeze-line, compatibility]
timestamp: 2026-08-28
sources:
  - schemas/compatibility.schema.json
  - schemas/customization.schema.json
  - AGENTS.md
---

# Component contract

Every component carries two schema-validated contract files. They live next to
the component's `helm/` + `manifests/` in this repository and are NOT inside the
published OCI artifact — `task package` tars only `kustomization.yaml` +
`manifest.yaml`, so a consumer reads both contracts from the catalog repository
at the tag they pin. Authoritative source: the schema descriptions in
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
- `provided_refs` / `required` - the consumer-input surface across four shapes: (a) env ConfigMap via `envFrom`, (b) mounted config file, (c) runtime Secret, (d) operator-assembled config via labelled CRs. Empty for cluster-agnostic components. `required` means exactly what it says: without it the workload does not function.
- `optional` - additive, absent by default: the things the artifact carries a **working baked default** for, which a consumer supplies only to change behaviour. Two of the four shapes are modelled. `env_keys` ([DR-0004](../decisions/DR-0004-optional-customization-keys.md)) - a scalar the rendered config reads through a placeholder (e.g. `${INGESTER_REPLICATION_FACTOR:1}`); entry fields `name`, `description`, `default`, optional `group`. `config_files` ([DR-0005](../decisions/DR-0005-optional-config-file-channel.md)) - a whole file the artifact ships **with working content** in a ConfigMap the workload already mounts; entry fields `path` (the file path, not the mountPath), `ref` (ConfigMap only), `key`, `description`, `default` (the baked content verbatim), optional `group`, with `(ref, key)` as the entry's identity. The consumer replaces the content via `source.kustomize.patches`, never by writing into the signed object. A secret-key / selector channel is added only when a component needs one. The two channels are disjoint in both shapes - a key or a file is either must-supply or has a default, never both.
- `sync_wave` - the ArgoCD sync-wave, pre-rendered as a platform property (string matching `^-?[0-9]+$`); the consumer does not patch it.
- `external_dependencies` - other components (`<sub-layer>/<component>`) that must exist in the cluster first.

Validated by `task validate:contract` (a required status check via
`contract-validate.yml`): structural shape against the schema, plus the seven
`optional`-block rules JSON Schema cannot express - `required.env_keys` and
`optional.env_keys[].name` are disjoint and the optional names are unique (S1/S2);
`required.config_files` and `optional.config_files` are disjoint on the `(ref, key)`
identity (S3); that identity is unique within each channel (S4); `path` is unique
across both channels together (S5); an optional file ref is never the secret ref
(S6); and an optional file ref IS the declared `provided_refs.config` (S7). Note:
validation is still structural typing plus those seven rules -
freeze-line **semantics** (each `required.*` entry maps to a real rendered ref, each
declared optional key matches a real `${KEY}` placeholder, each declared optional
file is actually mounted at the declared path) is not gated at rest; see
[DR-0001](../decisions/DR-0001-specification-driven-component-build.md) §D3,
[DR-0004](../decisions/DR-0004-optional-customization-keys.md) §Named residuals and
[DR-0005](../decisions/DR-0005-optional-config-file-channel.md) §Named residuals.

## Where the detail lives

- Field-by-field semantics: the `description` strings in `schemas/*.schema.json`.
- The freeze-line design (calibrated-friction, image-as-anchor): `talos-platform-docs/adr/0024`.
- The schema-contract-parity decisions for each schema: the schema `description` headers.

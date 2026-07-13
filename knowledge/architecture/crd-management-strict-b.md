---
type: architecture
title: CRD management (strict-B)
description: The strict-B CRD-split model - a separate -crds OCI artifact per CRD-shipping component, sync-wave ordering, and prune protection.
tags: [architecture, crd, argocd, sync-wave]
timestamp: 2026-07-11
sources:
  - AGENTS.md
  - Taskfile.yml
---

# CRD management (strict-B)

Authoritative source: `AGENTS.md` (§Sub-layer and component conventions - CRD
management) and `talos-platform-docs/adr/0028`.

Every component that ships chart-provided CustomResourceDefinitions publishes a
**separate** `<sub-layer>/<component>-crds` OCI artifact next to its workload
artifact. There is no inline-vs-separate per-component choice - the split is
mandatory (strict-B).

## Consumer wiring

The consumer wires **two** Argo `Application`s:

1. the `-crds` app at sync-wave `-1` with `Prune=false`, then
2. the workload app.

## The build gate

- A `crd-bearing: true` marker in `compatibility.yaml` drives the split and is the gate's oracle. (It lives in `compatibility.yaml` because `customization.yaml` is schema-locked `additionalProperties: false`.)
- `task validate:crd-split` (part of `task ci`) enforces split **correctness**: the `-crds` artifact renders more than zero CRDs and its workload sibling renders zero. It validates that a split pair is internally consistent - **not** completeness (a single component shipping CRDs inline without splitting is not flagged; reviewer judgment gates that).
- The split is deterministic: `yq 'select(.kind == "CustomResourceDefinition")'` over the combined render output, covering both helm- and raw-manifest-sourced CRDs.

## Cascade protection

CR-cascade protection is the **Argo layer** - `Prune=false` on the `-crds` app is
authoritative. `helm.sh/resource-policy: keep` is the Helm layer and is **not**
honored by Argo for its own prune decisions. `ServerSideApply=true` clears the
262 KB annotation limit on large CRDs.

## Out of scope

Operator-installed CRDs (Crossplane providers / XRDs) are handled by the
sync-wave readiness model, not by this convention.

## Where the detail lives

- Full convention text and the gate's structural keying: `AGENTS.md` §Sub-layer and component conventions.
- The gate implementation: the `validate:crd-split` target in `Taskfile.yml`.

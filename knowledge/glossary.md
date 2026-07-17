---
type: glossary
title: Glossary
description: Core terms of the talos-platform-apps catalog - component, sub-layer, capability, swap-class, freeze-line, strict-B, and the platform-layer terms.
tags: [glossary, terminology]
timestamp: 2026-07-16
sources:
  - AGENTS.md
  - catalog/README.md
  - catalog/capability-index.yaml
  - schemas/compatibility.schema.json
  - schemas/customization.schema.json
---

# Glossary

The authoritative definitions live in `AGENTS.md` and the schema descriptions
under `schemas/`; this glossary is the terse orientation.

## Structural units

- **Component** - the OCI distribution unit. Lives at `sub-layers/<sub-layer>/components/<component>/` and is published as an independently versioned, signed OCI artifact at `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>/<component>:<tag>`. Directory name == identity.
- **Sub-layer** - an organizational grouping of components (a directory grouping), **not** a distribution unit. Carries a `README.md` and an aggregate `compatibility.yaml` listing its components.
- **Stack** - a composition of several components (e.g. `kube-prometheus-stack`), documented in a sub-layer README. A stack is never a `components/` directory of its own.
- **Rendered output** - the `helm template` + raw-manifest concatenation under a component's `rendered/` directory. Gitignored; it is what gets packaged into the OCI artifact, never committed.

## Platform layers

- **Base** - the substrate (Talos + Cilium + ArgoCD + cert-approver), in the `talos-platform-base` repository.
- **Apps** - the catalog (everything that is not substrate), this repository.
- **Consumer** - a per-cluster repository that composes base + apps by referencing catalog components by tag and supplying cluster-specific overrides.

## Contracts and capabilities

- **Capability** - a stable interface a consumer composes against (e.g. `cnpg-postgres`), defined in `catalog/capability-index.yaml`. The tool implementing it is swappable.
- **swap_class** - the cost of swapping a capability's implementation: `drop-in`, `label-move` (both consumer-invisible), `data-migration`, `rewrite-required`, `consumer-change` (visible). See `catalog/README.md`.
- **Freeze-line** - the workload/config boundary declared in a component's `customization.yaml` (ADR-0024). The pre-rendered, signed workload is the baseline; the image digest is the hard consumer-admission anchor, most other fields are consumer-overlayable per-cluster.
- **Compatibility surface** - a component's declared `requires` / `provides` in `compatibility.yaml`: catalog-internal component dependencies, capability requirements, and the capabilities/API surface it provides.

## CRD management

- **strict-B** - the CRD-split model (`talos-platform-docs` ADR-0028): a component shipping chart-provided CustomResourceDefinitions publishes a **separate** `<sub-layer>/<component>-crds` OCI artifact; the consumer wires the `-crds` app at sync-wave `-1` with `Prune=false`, then the workload.
- **crd-bearing** - the `compatibility.yaml` marker that drives the split and is the build gate's oracle (`task validate:crd-split`).

## Ordering

- **sync-wave** - the ArgoCD `argocd.argoproj.io/sync-wave` ordering annotation. Pre-rendered into the manifest as a platform property (`customization.yaml` `sync_wave`), not a consumer-tunable field.

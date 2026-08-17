---
type: architecture
title: Platform-layer model
description: The base / apps / consumer division of labor that structures the Devoba Talos platform.
tags: [architecture, layers, oci]
timestamp: 2026-08-17
sources:
  - AGENTS.md
---

# Platform-layer model

Authoritative source: `AGENTS.md` (§Repository Purpose) and
`talos-platform-docs/adr/0009-platform-layer-model.md`.

The platform is split into three co-equal inputs a cluster integrates:

- **Base** - the substrate: Talos + Cilium + ArgoCD + cert-approver. Lives in `talos-platform-base`.
- **Apps** - the catalog: everything that is not substrate, published as signed OCI artifacts. This repository.
- **Consumer** - composition: a per-cluster repository that references exactly the base and apps components it needs, by tag, and supplies cluster-specific overrides.

## Load-bearing consequences

- **Apps does not depend on base.** A component's `compatibility.yaml` carries **no** `talos-platform-base` line. Base and apps are co-equal inputs the consumer integrates; a component declares only catalog-internal component dependencies plus capability requirements, and the consumer maps capabilities to concrete base/apps versions.
- **No cluster identity here.** Node IPs, hostnames, TLS CNs, real secrets, and cluster-specific Helm overrides live in the consumer repositories, never in this catalog.
- **No cluster apply from this repo.** This repository publishes OCI artifacts; the cluster apply runs via ArgoCD in the consumer repositories. There is no direct `kubectl apply` against clusters from here.
- **Argo `Application` definitions live in the consumer repo**, one per component with a sync-wave annotation. This repo carries local-test templates only, in two places: `local/argo-apps/<sub-layer>/<component>.yaml`, which `task local:apply` fans out wholesale, and `local/fixtures/<sub-layer>/<component>/`, for a component whose stack is too heavy to attach to every unrelated E2E in its sub-layer and is therefore applied by hand.

## Where the detail lives

- The division of labor and the "NOT in this repo" list: `AGENTS.md` §Repository Purpose.
- The multi-layer OCI distribution rationale: `talos-platform-docs/adr/0009-platform-layer-model.md`.
- The capability contract that lets the consumer map interfaces to versions: [Capability-layer model](capability-layer-model.md).

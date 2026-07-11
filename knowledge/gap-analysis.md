---
type: reference
title: Gap analysis
description: A living inventory of documentation, architecture/capability, and gate/coverage gaps across the catalog.
tags: [gap-analysis, coverage, documentation, capability, gates]
timestamp: 2026-07-11
sources:
  - catalog/capability-index.yaml
  - knowledge/decisions/DR-0001-specification-driven-component-build.md
  - AGENTS.md
  - DOCUMENTATION.md
  - policies
  - Taskfile.yml
  - release-please-config.json
  - .release-please-manifest.json
---

# Gap analysis

A **living** inventory of what the catalog does not yet document, implement, or
mechanically gate. It is maintained, not one-shot: when a gap is closed, strike
it here and cite the closing change; when a source in `sources` changes,
re-verify the affected rows and bump `timestamp`.

Provenance discipline: rows marked **[census 2026-06-24]** derive from the dated
snapshot in [DR-0001 §Evidence](decisions/DR-0001-specification-driven-component-build.md)
and are method-sensitive counts — re-derive before quoting. Rows marked
**[verified 2026-07-11]** were checked against the live tree while authoring this
concept. Severity is a rough triage, not a tracked priority.

Catalog scale at authoring: **12 sub-layers, 61 components** (git-tracked;
`sub-layers/monitoring/` and other on-disk directories are gitignored/stale and
not part of the catalog). See [the sub-layer reference](reference/sub-layers/index.md).

## 1. Documentation gaps

| Gap | Evidence | Severity |
|---|---|---|
| `hubble` README omits OCI path, `## Sync-wave`, and any ADR reference (fails the DOCUMENTATION.md content checklist on all three) | `sub-layers/observability/components/hubble/README.md` [verified 2026-07-11] | blocks-understanding |
| `synology-csi` README documents no sync-wave although `customization.yaml` sets `sync_wave: "0"` | `sub-layers/storage-block/components/synology-csi/README.md` | drift |
| The build spec understates the enforced policy set — it says `policies/` "carries essentially one enforced rule" while **six** rego rules are live | `.claude/skills/build-catalog-component/CONVENTIONS.md` (~L198); cf. `policies/README.md` | drift |
| German-language bodies remain in tracked docs that the English mandate targets (migration backlog, not new) | `lifecycle/crossplane/README.md`, `secrets/ca-clusterissuer/README.md`, `storage-objects/garage-buckets/README.md`, and inline comments in `registry/harbor/helm/harbor.yaml` | hygiene |
| **Public-repo hygiene**: two READMEs name a specific consumer environment domain in prose (the value is intentionally not repeated here), which the DOCUMENTATION.md placeholder rule forbids in a public repo | `sub-layers/secrets/README.md` (~L24), `sub-layers/secrets/components/ca-clusterissuer/README.md` (~L3, L11) [verified 2026-07-11] | drift |
| No architectural diagram anywhere in-repo; C4/architecture is deferred to `talos-platform-docs`, so a new operator gets no in-repo picture | repo-wide (no mermaid/flowchart in any tracked `.md`) | hygiene |
| No consolidated cross-sub-layer sync-wave / dependency-order overview; the global ordering is reconstructable only per-component | each `sub-layers/<sl>/README.md` lists only its own components | hygiene |
| Thin component READMEs worth a completeness pass vs DOCUMENTATION.md | `garage-buckets`, `clustersecretstore-defaults`, `crossplane`, `velero`, `grafana` READMEs | hygiene |
| This bundle's own topic concepts are still orientation-depth for several topics; full consolidation into the primary-home role (see [DR-0002](decisions/DR-0002-knowledge-bundle-as-primary-doc-home.md)) is in progress | `knowledge/` | hygiene |
| A host security hook blocks writes to any path carrying a bare `secrets` segment — a documented false-positive on the `secrets` sub-layer (secret *tooling*, not material) that can silently blind writers/reviewers; the sub-layer concept is named `secret-management.md` to work around it, and the hook pattern should be narrowed to file-level (`.env`/`*.pem`/`*.key`), never a bare path segment | project `CLAUDE.md` §Host-permission interaction; `hooks/block-secret-paths.sh` [verified 2026-07-11: write to `secrets.md` blocked] | drift |

## 2. Architecture and capability gaps

| Gap | Evidence | Severity |
|---|---|---|
| `secret-config-declarative` capability's active impl is `vault-config-operator`, but only the **`-crds` half ships** — the workload component `secrets/vault-config-operator` is absent (orphan strict-B half) | `catalog/capability-index.yaml`; `sub-layers/secrets/components/` has `vault-config-operator-crds` and no workload sibling [verified 2026-07-11, cross-confirmed by two independent surveys] | MED |
| Components ship but their capability contract is undefined (`capabilities: [] # TODO`): `velero`→`backup`, `harbor`→`oci-registry`, `ipxe`→`bare-metal-boot` | the four `compatibility.yaml` files | MED |
| Two CSI drivers implement an **undefined** capability: `democratic-csi` and `synology-csi` both `# TODO` a `block-storage`/`csi-iscsi` capability the index does not define (it has only `block-storage-replicated`/`block-storage-local`) | `storage-block/{democratic-csi,synology-csi}/compatibility.yaml`; `catalog/capability-index.yaml` | MED |
| `bare-metal-boot` wired inconsistently across its two halves: `booter` declares `{id: bare-metal-boot, role: proxydhcp}` (and without `swap_class`), while sibling `ipxe` carries `capabilities: []` + a TODO | `lifecycle/{booter,ipxe}/compatibility.yaml` | MED |
| Capabilities with no `status: active` catalog implementation: `kafka-managed` and `rabbitmq-managed` (all impls `considered`/`candidate`) — messaging domain unserved | `catalog/capability-index.yaml` [verified 2026-07-11] | MED |
| Capabilities defined against a non-catalog deployer without the index annotating it as such: `admission-policy` (kyverno, consumer-deployed per ADR-0018) | `catalog/capability-index.yaml` | LOW |
| `synology-csi` is documented as **deprecated / non-functional on Talos** yet still ships as a component | `sub-layers/storage-block/components/synology-csi/README.md` | LOW |
| `identity/dex` and `lifecycle/booter` declare a capability without a `swap_class` (older contract shape) | the two `compatibility.yaml` files | LOW |
| 6 components lack the required `customization.yaml` (freeze-line contract): `velero`, `booter`, `grafana`, `ca-clusterissuer`, `clustersecretstore-defaults`, `garage-buckets` | `sub-layers/*/components/*/` [verified 2026-07-11] | MED |

## 3. Gate and coverage gaps

The pattern DR-0001 documents: axes with a deterministic gate stay consistent;
axes with no gate (or only a shape gate) drift. These are the still-open holes
where the pipeline rests on reviewer judgment. All DR-0001 D1-D4 decisions were
**verified un-landed** as of 2026-07-11 (no `workload_type`, no `values.schema.json`,
no `task component:new`, no freeze-line semantic gate, no `declared==render` PSA
comparator).

| Gap | Evidence | Severity |
|---|---|---|
| Workload values are un-gated free-form YAML (no `values.schema.json`, no values-intent check) — DR-0001 D2 | [census 2026-06-24] + [verified 2026-07-11: no schema files] | unchecked-correctness |
| PSA level-choice (the too-loose / under-labelling direction) is un-gated; `pod_security_conformance` gates only the too-strict direction; `privileged` level itself un-gated — DR-0001 D1 | `policies/conformance/pod_security_conformance.rego` | unchecked-correctness |
| Freeze-line **semantics** (`required.*` ↔ rendered ref) un-gated; `validate:contract` checks structure only — DR-0001 D3 | 27/37 vacuous freeze-lines [census 2026-06-24, upper bound] | unchecked-correctness |
| Namespace sole-claimant uniqueness un-gated (cross-component name collisions not mechanically caught) | AGENTS.md; no rego rule | unchecked-correctness |
| Capability referential integrity has no static gate — `catalog/capability-index.yaml` is unreferenced in `Taskfile.yml`; `requires`/`provides` id resolution is build/evaluator-time only | [verified 2026-07-11: 0 Taskfile references] | unchecked-correctness |
| Sync-wave **value**-correctness un-gated; `validate:contract` checks only the `^-?[0-9]+$` format | `Taskfile.yml validate:contract` | unchecked-correctness |
| crd-split **completeness** un-gated: `validate:crd-split` checks a split pair's correctness, not whether a CRD-shipping single component *should* have split (`cert-manager` ships CRDs inline) | `Taskfile.yml validate:crd-split`; `secrets/cert-manager` | scope-residual |
| No `OKF_VERSION` ↔ checksum parity gate (a version bump re-pins 4 checksums by hand; a wrong one fails closed only on that platform) | `Taskfile.yml okf:install` [verified 2026-07-11] | scope-residual |
| Deferred conftest rules named in ADR-0018/PNI but not yet implemented: `gateway_api_only`, `helm_chart_source_official`, the `platform/` PNI-v2 set (`capability_selectors`, `reserved_labels`, …) | `policies/README.md` | unchecked-correctness |
| Trivy CVE scan scope residuals: operator operands (`RELATED_IMAGE_*`), Crossplane `spec.package` xpkg, nested `image:{repository,tag}`, kubevirt `virt-*`, untagged CR image keys | AGENTS.md §ADR-Abdeckung | scope-residual |
| Advisory-not-blocking gates (do not block a merge today): `trivy-cve` PR check, publish-time `trivy-images-of` (`continue-on-error`), the weekly sweep, and `commit-lint` (still pending as a required context) | `security-scan.yml`, `oci-publish.yml`, AGENTS.md | advisory-only |
| Conftest ↔ consumer-Kyverno defense-in-depth is kept consistent by hand (drift caught only by the M2-deferred reviewer) | `policies/README.md` | unchecked-correctness |

## Non-gaps (checked, confirmed fine)

- Aggregate `compatibility.yaml` ↔ component-directory parity is clean for all 12 sub-layers.
- All three capability `requires` ids (`cnpg-postgres`, `s3-object`, `redis-managed`) resolve in the index; no dangling *index-defined* references.
- `.release-please-manifest.json` lags `release-please-config.json` by one (`local-path-provisioner`), which is the **expected** state for a not-yet-released component — release-please records its version on first release; `validate:release-config` guard E requires only *tagged* components in the manifest. Not a defect.
- `sub-layers/monitoring/` and the untracked `renovate` / `kube-prometheus-stack` directories are gitignored/stale, not phantom components.

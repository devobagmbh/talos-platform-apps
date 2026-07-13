---
okf_version: "0.1"
---

# talos-platform-apps — Knowledge Bundle

An [Open Knowledge Format](SPEC.md) v0.1 bundle: the **primary documentation
home** for this repository ([DR-0002](decisions/DR-0002-knowledge-bundle-as-primary-doc-home.md)).
It consolidates the catalog's architecture, contracts, gates, workflows,
per-sub-layer reference, and decision records into one navigable, self-describing
home for humans and agents. A catalog gap analysis is tracked separately in issue #523. Concepts are
authoritative and self-contained for their topic; each cites its `sources` for
provenance and carries a verification `timestamp`.

`AGENTS.md` remains the machine-readable **conventions** source of truth and
`DOCUMENTATION.md` the doc-authoring standard; this bundle documents and orients
to them without restating their normative rules verbatim. Component and sub-layer
READMEs migrate into the bundle perspectively (DR-0002); until consolidated, a
component is described in both places (a bounded, tracked duplication, not a
permanent second source of truth).

## Architecture

- [Platform-layer model](architecture/platform-layer-model.md) - base / apps / consumer division of labor.
- [Capability-layer model](architecture/capability-layer-model.md) - capability as stable interface, tool as swappable implementation.
- [OCI distribution model](architecture/oci-distribution-model.md) - the component as the OCI unit; directory == identity.
- [CRD management (strict-B)](architecture/crd-management-strict-b.md) - separate `-crds` artifact, sync-wave ordering, prune protection.

## Reference

- [Sub-layer reference](reference/sub-layers/index.md) - the full catalog mapped, one concept per sub-layer (12 sub-layers, 62 components).
- [Component contract](reference/component-contract.md) - `compatibility.yaml` + `customization.yaml` (the freeze-line).
- [Policy and CVE gates](reference/policy-and-cve-gates.md) - Conftest misconfig gate + Trivy vulnerability gate.
- [CI and merge gates](reference/ci-and-merge-gates.md) - required status checks + branch protection.
- [Release automation](reference/release-automation.md) - release-please, per-component tags, publish flow.

## Workflows

- [Catalog build pipeline](workflows/catalog-build-pipeline.md) - plan -> build -> ship, judge-builder separation.
- [Issue and PR lifecycle](workflows/issue-pr-lifecycle.md) - status state machine, claim protocol, PR gates.

## Decisions

- [Decision records](decisions/index.md) - repo-local decision records (distinct from the platform ADRs).

## Reference material

- [Glossary](glossary.md) - component, sub-layer, capability, swap-class, freeze-line, strict-B, and the layer terms.
- [OKF specification](SPEC.md) - pinned upstream copy of the Open Knowledge Format v0.1 draft.
- [Log](log.md) - bundle changelog.

## Conventions of this bundle

Concept frontmatter (OKF requires only a non-empty `type`; the rest is this
repo's convention, documented here so it is discoverable and enforced by review,
not by the CLI):

- `type` - closed vocabulary matching the categories: `architecture`, `reference`, `workflow`, `decision`, `glossary`.
- `title` - the concept's display title.
- `description` - one sentence, reused verbatim as the link description in this index.
- `tags` - free-form topic tags.
- `timestamp` - the date this concept's present-tense claims were last verified against `sources`.
- `sources` - repo-relative paths the concept derives from; the staleness contract is that a concept is re-verified when a listed source changes.

Link rule: links **inside** this bundle are relative Markdown links; references to
anything **outside** the bundle (`AGENTS.md`, `schemas/`, external ADRs) are
inline code spans, never links - so the bundle stays portable and the
`link-target` gate stays meaningful.

Schema-contract-parity for the frontmatter convention: (1) the `type` value-set
is closed (the five above); other producer keys are tolerated per OKF but not
used here. (2) Duplicate frontmatter keys are a YAML authoring error - readers
treat the file as malformed rather than last-wins. (3) No version field on
concepts; the bundle version is `okf_version` in this index, and the OKF spec
version is pinned in [SPEC.md](SPEC.md). (4) Bundle files are trusted
repo-internal docs (same class as `DOCUMENTATION.md`); no untrusted-data
sentinel applies. (5) `timestamp` and `sources` are mutable-in-place on each
re-verification; concept bodies are edited in place, decision records are
append-only (corrections land as dated editorial notes).

---
type: decision
title: "DR-0002 — The knowledge/ bundle as the primary documentation home (OKF)"
description: Adopt an Open Knowledge Format bundle as the primary, consolidating documentation home for this repo, with a living gap analysis.
tags: [decision, documentation, okf, knowledge-bundle, sot]
timestamp: 2026-07-11
sources:
  - knowledge/index.md
  - AGENTS.md
  - DOCUMENTATION.md
---

# DR-0002 — The knowledge/ bundle as the primary documentation home

- **Status:** Accepted
- **Date:** 2026-07-11
- **Record class:** repo-local decision record (`knowledge/decisions/`), distinct from the platform-wide ADR series in `talos-platform-docs/adr/`.
- **Scope:** where this repository's *documentation of record* lives and how it is validated. Does not change the OCI/build/gate contracts (those remain owned by `AGENTS.md`, `schemas/`, `policies/`).

## Context

Documentation was scattered across three shapes with no single navigable home:
`AGENTS.md` / `DOCUMENTATION.md` (conventions), a `docs/` tree holding exactly one
decision record, and 61 co-located component READMEs plus 12 sub-layer READMEs.
There was no consolidated architecture view, no cross-sub-layer dependency
overview, no in-repo diagram, and no systematic account of what is *not* yet
documented, implemented, or gated. A reader — human or agent — had to reconstruct
the whole from fragments.

## Decision

Adopt an **Open Knowledge Format (OKF) v0.1 bundle** at `knowledge/` as the
**primary documentation home** of this repository, and resolve documentation
duplication by **consolidation into the bundle**, not by pointer indirection.

- The bundle is a directory of Markdown concept files with YAML frontmatter,
  validated by `task okf:validate` (structural conformance + a link-resolution
  gate). It is authored to be read by both humans and agents.
- Concepts are **authoritative and self-contained** for their topic; each cites
  its `sources` (repo-relative paths) for provenance and carries a `timestamp`
  of last verification. The staleness contract is that a concept is re-verified
  when a listed source changes.
- Coverage: deep topic concepts (architecture, contracts, gates, workflows), one
  **reference concept per sub-layer** (the full catalog mapped), the migrated
  decision records, and a glossary. A catalog **gap analysis** (documentation,
  architecture/capability, gate/coverage) is tracked in issue #523, not committed
  as a bundle concept.
- `AGENTS.md` remains the machine-readable **conventions** source of truth and
  `DOCUMENTATION.md` the doc-authoring standard; the bundle documents and orients
  to them and does not restate their normative rules verbatim.

## Consequences

### Positive

- One navigable home for humans and agents, self-describing and diffable.
- The gap analysis (issue #523) makes documentation, capability, and gate coverage
  a first-class, tracked artifact rather than tacit knowledge.
- The `sources` + `timestamp` convention gives every claim a provenance and a
  staleness signal.

### Negative / cost

- **Consolidation vs the README-per-component convention.** `AGENTS.md` §Coding
  Style mandates a README per sub-layer AND per component. This decision does NOT
  delete those READMEs; it establishes the bundle as the primary home into which
  their content migrates **perspectively** (incrementally), and the sub-layer
  reference concepts are the first consolidation. Until a component README is
  consolidated, it and the bundle both describe the component — a bounded,
  tracked duplication (itself a documented gap in issue #523), not a permanent
  second source of truth.
- Ongoing maintenance: concepts must be re-verified against `sources` on change.

### Relationship to DR-0001

DR-0001 governs the `.claude/` build pipeline and per-component contract surface;
this record governs the documentation home. They are orthogonal. DR-0001 was
relocated verbatim into this bundle as part of adopting it.

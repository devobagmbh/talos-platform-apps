# Bundle Update Log

## 2026-07-13

- **Self-maintenance**: added the knowledge-bundle maintenance directive to `AGENTS.md` (§ Knowledge-bundle maintenance) and its mechanical backstop `task okf:freshness` (advisory; a `sources:` change in a PR without a concept `timestamp:` bump is flagged), run by `okf-freshness.yml`. Adopted hand-written from the upstream `openknowledge` `docs` rule; blocking flip tracked in #541.
- **Freshness re-verification**: bumped `reference/sub-layers/secret-management.md` for #524 — added the `vault-config-operator` workload row and resolved the former `vault-config-operator-crds` orphan-half gap note.

## 2026-07-11

- **Initialization**: created the `knowledge/` Open Knowledge Format v0.1 bundle as a curated orientation layer over the catalog's architecture, contracts, gates, and workflows.
- **Migration**: relocated the repo-local decision record `docs/decisions/0001` verbatim into `decisions/DR-0001`; the `docs/` tree was removed.
- **Spec**: stored a pinned upstream copy of the OKF v0.1 draft in `SPEC.md`.
- **Tooling**: the `openknowledge` CLI (pinned v0.4.0) validates the bundle via `task okf:validate`; a `list --json` link gate hard-fails on unresolved or bundle-escaping links (the CLI's own `validate` reports those as warnings only).
- **Primary-home expansion**: established the bundle as the primary documentation home ([DR-0002](decisions/DR-0002-knowledge-bundle-as-primary-doc-home.md)); added one [reference concept per sub-layer](reference/sub-layers/index.md) (12 sub-layers, 61 components). A catalog gap analysis (documentation, architecture/capability, gate/coverage) is tracked in issue #523.

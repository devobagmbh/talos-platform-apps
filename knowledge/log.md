# Bundle Update Log

## 2026-07-11

- **Initialization**: created the `knowledge/` Open Knowledge Format v0.1 bundle as a curated orientation layer over the catalog's architecture, contracts, gates, and workflows.
- **Migration**: relocated the repo-local decision record `docs/decisions/0001` verbatim into `decisions/DR-0001`; the `docs/` tree was removed.
- **Spec**: stored a pinned upstream copy of the OKF v0.1 draft in `SPEC.md`.
- **Tooling**: the `openknowledge` CLI (pinned v0.4.0) validates the bundle via `task okf:validate`; a `list --json` link gate hard-fails on unresolved or bundle-escaping links (the CLI's own `validate` reports those as warnings only).
- **Primary-home expansion**: established the bundle as the primary documentation home ([DR-0002](decisions/DR-0002-knowledge-bundle-as-primary-doc-home.md)); added one [reference concept per sub-layer](reference/sub-layers/index.md) (12 sub-layers, 61 components) and a living [gap analysis](gap-analysis.md) spanning documentation, architecture/capability, and gate/coverage gaps.

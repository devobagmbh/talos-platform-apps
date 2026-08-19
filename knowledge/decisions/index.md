# Decision records

Repo-local decision records governing **this** repository's build harness and
conventions. These are distinct from the **platform-wide** ADR series, which
lives in the `talos-platform-docs` repository under `adr/` (referenced from
concepts as inline paths, e.g. `talos-platform-docs/adr/0009-platform-layer-model.md`).

## Accepted

- [DR-0001 — Specification-driven catalog component build](DR-0001-specification-driven-component-build.md) - adopt a specification-driven, render-bound component build (render-derived PSA level, per-component values contract, deterministic scaffold) over copy-from-neighbor. Accepted 2026-06-24.
- [DR-0002 — The knowledge/ bundle as the primary documentation home](DR-0002-knowledge-bundle-as-primary-doc-home.md) - adopt an OKF bundle as the primary, consolidating documentation home, with a living gap analysis. Accepted 2026-07-11.
- [DR-0003 — Machine-readable topology-variant contract](DR-0003-topology-variant-contract.md) - express mutual-exclusion + either-satisfies between topology-sibling components (loki/loki-distributed, tempo/tempo-distributed) in one central, schema-validated, ci-gated `catalog/topology-groups.yaml`, leaving the capability index and every `requires:` key unchanged. Accepted 2026-07-23.
- [DR-0004 — Optional consumer-supplied env keys in the customization contract](DR-0004-optional-customization-keys.md) - add an additive top-level `optional` block so a component can declare env keys that carry a working baked default, keeping `required` strictly the must-supply channel; the two rules JSON Schema cannot express (cross-channel disjointness, name uniqueness) are enforced by `task validate:contract` over the real component files. Accepted 2026-08-16.

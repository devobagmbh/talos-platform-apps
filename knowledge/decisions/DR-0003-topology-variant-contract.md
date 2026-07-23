---
type: decision
title: "DR-0003 — Machine-readable topology-variant contract (catalog/topology-groups.yaml)"
description: Express mutual-exclusion + either-satisfies between topology-sibling components in one central, schema-validated, ci-gated contract file, without touching the capability index, any requires: key, or any component compatibility.yaml.
tags: [decision, catalog, topology-variant, compatibility, contract, observability]
timestamp: 2026-07-23
sources:
  - catalog/topology-groups.yaml
  - schemas/topology-groups.schema.json
  - catalog/capability-index.yaml
  - catalog/README.md
  - AGENTS.md
  - sub-layers/observability/components/loki/compatibility.yaml
  - sub-layers/observability/components/loki-distributed/compatibility.yaml
  - sub-layers/observability/components/tempo/compatibility.yaml
  - sub-layers/observability/components/tempo-distributed/compatibility.yaml
---

# DR-0003 — Machine-readable topology-variant contract

- **Status:** Accepted
- **Date:** 2026-07-23
- **Issue:** #733
- **Record class:** repo-local decision record (`knowledge/decisions/`), distinct from the platform-wide ADR series in `talos-platform-docs/adr/`.
- **Scope:** how the catalog expresses that two components are mutually-exclusive topology alternatives of the same product, and that a concrete dependency pin to one is satisfiable by either. Does not change the OCI/build contract, the capability index, or any consumer dependency key.

## Context

`observability/loki` and `observability/loki-distributed` (and, identically, `observability/tempo` / `observability/tempo-distributed`) are alternative deployment topologies of the same product. A consumer runs exactly one of each pair. `schemas/compatibility.schema.json` is `additionalProperties: false` with only `requires` / `provides` / `crd-bearing` / `resource_policy` — there was no machine-readable way to say "these two are alternatives, never co-deployed", nor that a concrete `requires: observability/loki` pin (written by `alloy`, `alloy-singleton`, `grafana`; and `requires: observability/tempo` by `alloy`, `grafana`) is satisfiable by either member. The exclusion lived only in README prose and sub-layer aggregate comments.

## Decision

Adopt a single central contract file `catalog/topology-groups.yaml`, validated by a dedicated JSON-Schema (`schemas/topology-groups.schema.json`) and a self-contained gate `task validate:topology-groups` wired into `task ci`. Each group lists the mutually-exclusive members of one product and names the default (primary) topology.

```yaml
groups:
  - id: loki
    kind: mutual-exclusion
    default: observability/loki
    members: [observability/loki, observability/loki-distributed]
  - id: tempo
    kind: mutual-exclusion
    default: observability/tempo
    members: [observability/tempo, observability/tempo-distributed]
```

- **Mutual-exclusion** — a consumer deploys exactly one member of a group.
- **Either-satisfies** — a concrete `requires:` pin to any member is satisfied by any member of that group. The `requires:` key stays a concrete `<sub-layer>/<component>`, so the `catalog/README.md` rule forbidding a capability-id substitution for a tool-specific surface is unweakened. Either-satisfies is a contract-expressibility property computed from the unchanged pin plus this central file; no consumer-side key shape changes.

## Why a central file, not a per-component field

A per-component `topology_group` field on each variant's `compatibility.yaml` was rejected. This repo blocks more than one component per commit (`lint:commit-scope`) and per PR (`lint:pr`), so four variants would force four component PRs plus a fifth, strictly ordered; each component-path commit path-maps to a release-please version bump; and a "group has at least two members" assertion over the live corpus deadlocks on the first member added (a one-member group reds `ci`). The central file declares all members together in one 0-component PR — no ordering, no version bump, no in-flight one-member state, no deadlock.

The gate reads **only** the central file plus directory existence. It never opens a component `compatibility.yaml` capability set. A gate that re-derived capability-set identity from each member on every PR would red `ci` whenever a routine one-component capability edit diverged one member's set from its sibling, and the fix would be a blocked two-component PR — the same deadlock class on the evolution path.

## Same-product-ness is review-enforced and necessary-not-sufficient

There is no sound mechanical oracle for "these two components are the same product". Capability-set identity is **necessary but not sufficient**:

- it false-accepts genuine tool-swaps — `loki` and `victoria-logs` share `{logs-storage, logs-query}`, `tempo` and `jaeger` likewise — which is exactly the tool substitution the issue's acceptance criterion forbids;
- it false-accepts empty capability sets — every `-crds` strict-B half and api-surface-only component carries `capabilities: []`;
- it false-rejects a legitimate distributed variant that exposes an extra operational surface.

So same-product-ness is asserted by the author (the `kind: mutual-exclusion` declaration) and confirmed by human review, not proven by the gate. The review is not merely convention: `catalog/topology-groups.yaml` is in the babysit `pr:triage` governance-withhold set (`Taskfile.yml`), so a future single-file edit to the contract is mechanically forced to a human rather than auto-approvable under a code-owner identity. Beyond that narrow mechanical backing, the controls are the author-declared `kind` and the `AGENTS.md` Topology-variants naming rule. This is **not** a general "mandatory CODEOWNERS review" mechanism wired for this file class — the backing is exactly the one withhold glob.

## Expressibility only — the runtime endpoint difference is NOT fixed here

Either-satisfies is expressibility only. The runtime write-endpoint **differs** between topologies: `alloy` must target `loki-distributed-distributor`, not `loki`. Swapping a consumer from one topology to the other therefore still requires a consumer-overlay endpoint change (ADR-0024 kustomize patch). This contract does **not** fix that operational bug and must not create false confidence about it. The limitation is stated prominently in the `catalog/topology-groups.yaml` header and was surfaced to the human at the plan-approval gate.

## Why the capability index stays tool-keyed

`catalog/capability-index.yaml` is byte-unchanged. Its `implementations[]` axis is tool-keyed (`{name: loki}`, `{name: tempo}`), and both topology artifacts already legitimately claim the same capability ids. Adding a `loki-distributed` / `tempo-distributed` implementation entry would misrepresent a topology as a second swappable tool — the acceptance criterion explicitly forbids it. The topology axis belongs in the central file, not as a second tool in the index.

## mimir is excluded (Hard Constraint)

`mimir` is the recorded legacy bare-name exception (`AGENTS.md` Topology variants, a Hard Constraint): its bare name already denotes the `mimir-distributed` microservices topology and it has no sibling to be mutually exclusive with. The issue's "mimir is an obvious next candidate" wording is reconciled here by recording the exclusion, not by grouping mimir. A future third pair (a genuine two-topology product) is added as a new group under harness-evolution review, with the gate and fixtures extended in the same PR.

## Named residuals

- **Tree-to-central completeness gap.** `member-dir-exists` enforces central-to-tree only (every declared member must be a real dir). A future `foo-distributed` variant added to the tree **without** registering its group in the central file silently yields an incomplete contract. A sound mechanical completeness check is infeasible — a `*-<topology>` suffix heuristic false-positives on the role-additive `alloy` trio. Backstops: human review plus the `AGENTS.md` topology-variant naming rule. An optional best-effort advisory warning could flag an unregistered `*-distributed`-suffixed dir, but that would not be a hard gate and would not be full parity; do not claim tree-central parity.
- **Member-rename / topology-retirement lifecycle coupling.** The `member-dir-exists` check couples the central file to the component tree. Renaming or retiring a member dir makes its central member id stale and reds `ci` until the central file is edited in the same change; retiring one topology of a two-member group hits the schema `minItems: 2`, so the whole group must be dropped (a single-member group is not expressible). Narrow (fires only on member rename/removal, not routine edits) and resolvable via sequential single-file edits — documented so a future maintainer expects it.
- **Flat bare-id namespace constraint.** The id-unique check plus the leaf-equals-id check together force each group `id` to equal the bare component name AND be globally unique across groups. Two components sharing a bare name in different sub-layers that both grew topology variants could not both be grouped under this scheme. Latent — only loki/tempo exist today — but noted so a future name collision is anticipated.
- **capability-index same-product auto-approve exposure.** `catalog/capability-index.yaml` carries the identical same-product-review exposure that the `pr:triage` withhold now closes for `catalog/topology-groups.yaml`, and it is pre-existing. It is deliberately NOT fixed here (that would need a broader `catalog/` withhold, out of this issue's scope). Recorded as a separate hardening follow-up issue to file (number to be back-filled once filed).

## Action items

- File a `talos-platform-docs` issue for the ADR-0021 amendment (the capability-layer model gains the topology-variant axis). Number to be back-filled once filed.
- File the `catalog/capability-index.yaml` same-product hardening follow-up issue (see the residual above). Number to be back-filled once filed.

## Consequences

Purely additive and repo-only: a new central file, its schema, one gate plus its red-green test, one narrowed `pr:triage` withhold glob, and documentation. No component `compatibility.yaml`, no consumer `requires:` key, and no `swap_class` value changes. Because no `sub-layers/*/components/*` path is touched, release-please cuts no tag and no OCI artifact is republished. Rollback is a single revert of the one PR.

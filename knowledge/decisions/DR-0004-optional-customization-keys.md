---
type: decision
title: "DR-0004 — Optional consumer-supplied env keys in the customization contract"
description: Add an additive top-level `optional` block to the customization contract so a component can declare env keys that carry a working baked default, keeping `required` strictly the must-supply channel; enforce the two rules JSON Schema cannot express in task validate:contract.
tags: [decision, contract, customization, schema, adr-0024, consumer-overlay]
timestamp: 2026-08-16
sources:
  - schemas/customization.schema.json
  - schemas/testdata/customization-optional-valid.yaml
  - Taskfile.yml
  - AGENTS.md
  - knowledge/reference/component-contract.md
---

# DR-0004 — Optional consumer-supplied env keys in the customization contract

- **Status:** Accepted
- **Date:** 2026-08-16
- **Issue:** #794
- **Record class:** repo-local decision record (`knowledge/decisions/`), distinct from the platform-wide ADR series in `talos-platform-docs/adr/`.
- **Scope:** how a component declares a consumer-settable knob that is **not** mandatory. Does not change the OCI/build contract, the freeze line, `compatibility.yaml`, or any rendered artifact.

## Context

`customization.yaml` (ADR-0024 v2) modelled exactly one consumer-input channel: `required`, "what the consumer MUST supply". That is the right shape for `S3_ENDPOINT` — without it the workload does not function.

It is the wrong shape for the class #794 needs. Making `observability/mimir` reachable for a multi-node consumer means exposing knobs such as the ingester replication factor: the artifact renders `replication_factor: ${INGESTER_REPLICATION_FACTOR:1}`, so a consumer who sets nothing gets the working single-node default, and a consumer who sets `3` gets an HA ring — no catalog PR, no replacement of the signed config. Such a key has no home in the contract:

- Declaring it under `required` is a lie the schema would happily accept: it says "supply this or the workload does not function", which would make every existing single-node consumer non-conformant overnight, and `contract-validate` is a required check.
- Not declaring it at all makes the knob invisible. A consumer-facing override surface that exists only in a README is not a contract — nothing marks a rename as breaking, and the versioned binding surface argument that produced `exposed_selectors` applies identically here.

## Decision

Add a top-level `optional` object to `schemas/customization.schema.json`, sibling of `required`, absent by default, `additionalProperties: false`, containing exactly one property today: `env_keys`.

```yaml
optional:
  env_keys:
    - name: INGESTER_REPLICATION_FACTOR
      description: >-
        Drives ingester.ring.replication_factor. Raise only after the ingester
        replica count is at least as high.
      default: "1"
    - name: CHUNKS_CACHE_BACKEND
      description: Drives blocks_storage.bucket_store.chunks_cache.backend.
      default: ""
      group: chunks-cache
```

The channel boundary is the definition, not a style preference:

- `required` — the consumer MUST supply it or the workload does not function.
- `optional` — the artifact carries a working baked default; the consumer supplies a value only to **change** behaviour.

## Why entries are objects, and why `required` stays a bare string list

`required.env_keys` is a bare string array and stays one — it is an obligation list, and the component README carries the explanation. An optional key is different: an undeclared default is the single most useful fact about it (what happens if I set nothing?), and a knob whose effect is undocumented is not usable without reading the rendered config. So each entry carries `name`, `description` and `default` as **required** fields, plus an optional `group`.

The asymmetry is deliberate and is the reason the two channels are not merged into one field with a flag.

## Why `restart_required` was considered and not built

Every key in this class is consumed through `envFrom` and resolved by
`-config.expand-env=true` at container start. There is no key for which
`restart_required: false` would be true, so the field would have exactly one
valid value — negative documentation that implies a distinction the mechanism
does not have. It is a schema-reject fixture
(`customization-optional-item-unknown-key.yaml`) rather than an unbuilt idea, so
a future author who reaches for it hits a red gate and reads this record.

## Why only the env shape

`required` models four shapes (env keys, config files, secret keys, selector CRs). `optional` models one. A config-file / secret-key / selector optional channel has no user today, so its semantics would be unexercised: nothing would pin down what "an optional config file" means (mounted-but-empty? absent mount? default file baked in?). The block is `additionalProperties: false`, so adding a shape later is an explicit, reviewed schema change — which is the point.

## Why two rules live in the task, not the schema

JSON Schema cannot express either of these, and both are silent failures:

- **S1 — cross-channel disjointness.** A key in both channels is self-contradictory: the consumer cannot tell whether omitting it is legal.
- **S2 — name uniqueness.** YAML resolves duplicate mapping entries last-wins without a diagnostic, so a duplicated `name` silently discards the first entry's documentation. (`uniqueItems` does not help: the items are objects that differ in `description`.)

Both are asserted by `task validate:contract` **over the real component files**, not only over fixtures — a gate that is green over a fixture corpus while the rule goes unenforced on the catalog is the failure mode this explicitly avoids. `validate:contract` is a required status check (`contract-validate.yml`), so the enforcement point is PR merge.

## Why the fixture guard lives inside the task

`validate:compatibility` already carries its negative/positive fixture guard inline, gated on full-corpus runs. `validate:contract` now mirrors it rather than introducing a separate `test:` target, because the alternative would have had to be wired into `task ci` — and `validate:contract` is deliberately **not** in `task ci` (the customization contract rolls out per component; coupling the render pipeline to it is the wrong dependency, see the note under `ci:artifact`). A test in `task ci` whose subject runs in a different job is a split pair.

The semantic fixtures call the same shell function the component loop calls, so they bind the real code path rather than a copy of it.

## Schema-contract parity (all five, per the harness meta-rule)

Documented inline in the schema's `optional` description, summarised here:

1. **Closed field set** — `additionalProperties: false` at the block and item level.
2. **Duplicate keys** — file corruption, surfaced by S2 rather than left to the parser's silent last-wins.
3. **Version skew** — there is no version field, and the root is `additionalProperties: false`. A consumer holding a **vendored copy of the pre-`optional` schema REJECTS** a `customization.yaml` carrying the new key; it does not ignore it. That is the standard cost of a closed schema. Migration signal: the schema `$id` plus ADR-0024.
4. **Untrusted-data marker** — not applicable; this is a repo-SOT trusted-data file changed only by reviewed PR.
5. **Per-field mutability** — entries are mutable in place by the component author, **except** that renaming or removing a shipped key is a **breaking** change: env expansion falls back to the baked default silently, so a consumer who had set the old name loses their setting with no error signal.

## Named residuals

- **No render binding.** Nothing compares a declared key against the rendered config. A declared key with no matching `${KEY}` placeholder passes green, and a one-character mismatch between the contract and `helm/*.yaml` produces a knob that silently does nothing. This is the most likely defect class in any component adopting the block, and it has no detector today. A render-vs-contract placeholder check is the follow-up.
- **`group` is descriptive only.** Nothing validates that a consumer set every member of a group. It records a co-requirement for the reader; a consumer who sets a cache backend without its addresses gets whatever the workload does with that combination (for Mimir: a loud startup failure — but that is the workload's behaviour, not the contract's enforcement).
- **Version-skew cost is real.** Parity decision 3 means every consumer vendoring the schema must update it before adopting a component that carries `optional`. There is no forward-compatibility escape hatch short of opening the root, which would forfeit the closed-set property the contract relies on.
- **Channel classification is author-asserted.** No gate can tell whether a key genuinely has a working default; a component author could park a truly mandatory key under `optional` with a plausible-looking default. Review is the control.

## Action items

- Companion PR amending ADR-0024 in `talos-platform-docs` (the schema is that ADR's implementation), open before this change merges.
- File the render-vs-contract placeholder-check follow-up issue (number back-filled once filed).

## Consequences

Additive and repo-only: one schema block, ten fixtures, the two semantic checks and the fixture guard inside an existing task, plus documentation. No component file changes in this record's own change, so release-please cuts no tag and no OCI artifact is republished. Rollback is a single revert — **except** that it must be co-ordinated with any component that has adopted the block: reverting the schema alone makes that component's `customization.yaml` fail the required `validate-contract` check.

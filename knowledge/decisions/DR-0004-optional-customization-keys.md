---
type: decision
title: "DR-0004 — Optional consumer-supplied env keys in the customization contract"
description: Add an additive top-level `optional` block to the customization contract so a component can declare env keys that carry a working baked default, keeping `required` strictly the must-supply channel; enforce the two rules JSON Schema cannot express in task validate:contract; the artifact never sets a declared env key itself (task validate:env-keys over the render).
tags: [decision, contract, customization, schema, adr-0024, consumer-overlay]
timestamp: 2026-10-06
sources:
  - schemas/customization.schema.json
  - schemas/testdata/customization-optional-valid.yaml
  - Taskfile.yml
  - AGENTS.md
  - knowledge/reference/component-contract.md
  - schemas/testdata/env-keys
---

# DR-0004 — Optional consumer-supplied env keys in the customization contract

- **Status:** Accepted for the repo-local scope (this schema + its two task-enforced rules). **Extended (not superseded) by [DR-0005](DR-0005-optional-config-file-channel.md)**, which adds the `config_files` shape to the same `optional` block; everything this record decides about the env shape still holds unchanged. **Amended 2026-09-25 ([#838](https://github.com/devobagmbh/talos-platform-apps/issues/838))** by §No-shadowing: the artifact never sets a declared env key itself, enforced over the render by `task validate:env-keys`; no new schema keyword. The platform-wide companion — `talos-platform-docs` ADR-0037 — is still `proposed` and flips to `accepted` once this change is merged; this record does not ratify the platform decision on its behalf, and nothing in the schema or the gate depends on that flip.
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

Every key in this class is resolved by `-config.expand-env=true` at container
start. Whether a change rolls the pods is a property of the consumer's delivery
path (§No-shadowing), not of the key: through the env ConfigMap it never does,
through a patched container `env` literal it does unless the workload is
`OnDelete` or holds pods back with a `rollingUpdate.partition`. A per-key
`restart_required` would therefore assert something the key cannot know —
negative documentation that implies a distinction the key does not have. It is a schema-reject fixture
(`customization-optional-item-unknown-key.yaml`) rather than an unbuilt idea, so
a future author who reaches for it hits a red gate and reads this record.

## Why only the env shape

> **Since resolved for one shape.** [DR-0005](DR-0005-optional-config-file-channel.md) built the config-file channel once a component defined what it means (`observability/kube-state-metrics`, [#832](https://github.com/devobagmbh/talos-platform-apps/issues/832)) — the answer to the open question below is *default file baked in*. The reasoning in this section is what gated that addition, and it still gates `secret_keys` and `selector_crs`.

`required` models four shapes (env keys, config files, secret keys, selector CRs). `optional` models one. A config-file / secret-key / selector optional channel has no user today, so its semantics would be unexercised: nothing would pin down what "an optional config file" means (mounted-but-empty? absent mount? default file baked in?). The block is `additionalProperties: false`, so adding a shape later is an explicit, reviewed schema change — which is the point.

## Why two rules live in the task, not the schema

JSON Schema cannot express either of these, and both are silent failures:

- **S1 — cross-channel disjointness.** A key in both channels is self-contradictory: the consumer cannot tell whether omitting it is legal.
- **S2 — name uniqueness.** Two entries naming the same key contradict each other — they may carry different defaults and different descriptions, and nothing decides which holds; a consumer reads whichever they happen to see first. `uniqueItems` does not catch it: the entries are distinct array items the moment any field differs. (A duplicate mapping key *within* one entry is a different thing, and the YAML loader rejects that before the check runs.)

Both are asserted by `task validate:contract` **over the real component files**, not only over fixtures — a gate that is green over a fixture corpus while the rule goes unenforced on the catalog is the failure mode this explicitly avoids. `validate:contract` is a required status check (`contract-validate.yml`), so the enforcement point is PR merge.

## Why the fixture guard lives inside the task

`validate:compatibility` already carries its negative/positive fixture guard inline, gated on full-corpus runs. `validate:contract` now mirrors it rather than introducing a separate `test:` target, because the alternative would have had to be wired into `task ci` — and `validate:contract` is deliberately **not** in `task ci` (the customization contract rolls out per component; coupling the render pipeline to it is the wrong dependency, see the note under `ci:artifact`). A test in `task ci` whose subject runs in a different job is a split pair.

The semantic fixtures call the same shell function the component loop calls, so they bind the real code path rather than a copy of it.

## Schema-contract parity (all five, per the harness meta-rule)

Documented inline in the schema's `optional` description, summarised here:

1. **Closed field set** — `additionalProperties: false` at the block and item level.
2. **Duplicate names** — a contradiction the schema cannot see (distinct array items), surfaced by S2.
3. **Version skew** — there is no version field, and the root is `additionalProperties: false`. A consumer holding a **vendored copy of the pre-`optional` schema REJECTS** a `customization.yaml` carrying the new key; it does not ignore it. That is the standard cost of a closed schema. **`$id` is unchanged and is therefore NOT a staleness signal** — the only in-band signal a consumer gets is the validation error naming the unknown `optional` property; out of band it is this record plus ADR-0024. Bumping `$id` was considered and rejected: it would break every consumer's schema reference to buy a marker they only see after the rejection has already told them.
4. **Untrusted-data marker** — not applicable; this is a repo-SOT trusted-data file changed only by reviewed PR.
5. **Per-field mutability** — entries are mutable in place by the component author, with **two exceptions, both breaking and both silent**: renaming or removing a shipped key (env expansion falls back to the baked default, so a consumer who had set the old name loses their setting with no error signal), and **changing a shipped `default`** (it changes runtime behaviour for every consumer who left the key unset — the majority — with nothing in their cluster changing to signal it). Raising mimir's replication-factor default from `"1"` to `"3"` is schema-valid, semantics-valid, and would break every single-ingester deployment on next sync. Both classes are major-version changes with a migration note.

## No-shadowing: the artifact never sets a declared key (#838)

**Principle.** A consumer must be free to set the values their use case needs, and the artifact never renders a value that silently overrides consumer input.

**Why it needed a gate.** Kubernetes gives a container's `env` entry precedence over any `envFrom` source for the same name, with no error or event. An artifact that renders `env: [{name: X, value: "1"}]` for a declared key therefore defeats the documented ConfigMap path: the consumer sets `X=3`, the workload runs with `1`, and every gate is green. The same holds for a data key of a ConfigMap or Secret the artifact itself renders — the artifact would be supplying the value it declares the consumer supplies.

**Decision.** `task validate:env-keys` (in `task ci`, after `render`) fails a component when a name from `required.env_keys`, `required.secret_keys` or `optional.env_keys[].name` is

- the `name` of an `env` list entry anywhere in its render (containers, initContainers, an operator CR's `env` list), unless that entry's `valueFrom` reads the consumer's own `provided_refs.env` ConfigMap or `provided_refs.secret` Secret — such an entry carries the consumer's value, and it is the one artifact-side way to make the consumer win over a chart-baked `envFrom` value; or
- with the `envFrom` `prefix` applied, a data / stringData / binaryData key of a top-level ConfigMap or Secret that the artifact renders **and** a container reads via `envFrom`. A key of an object that is only mounted as files is not checked — it cannot shadow an env variable, and a file-shaped secret key such as `config.yaml` would otherwise collide with every config file's key;

and when the render contains a ConfigMap named like `provided_refs.env` or a Secret named like `provided_refs.secret` at all — those objects are consumer-authored, an artifact copy collides with the consumer's object of the same name and could feed a baked value under any key (a remap entry included), so this rule is what makes the `valueFrom` exemption safe; and when an `env` list carries a variable twice while one of the entries reads the consumer's ref (whichever entry comes last wins, so the rule is deliberately order-blind), and when an `optional.env_keys` name has neither a `${NAME}` nor a `${NAME:` placeholder in the render. The exact match matters: a declared name that is only a prefix of a longer placeholder (`LOKI_REPLICATION` against `${LOKI_REPLICATION_FACTOR:-1}`) is a knob no expander reads. Every `yq` status is captured, so an unevaluable file fails, and an unscoped run in which no component declares a key fails as vacuous. Hermetic red-green: `task test:env-keys` over `schemas/testdata/env-keys/` (one positive carrying consumer-sourced `valueFrom` entries, envFrom'd artifact objects and a mounted file key; one single-reason negative per condition; two unparseable inputs). On introduction it read 64 local component contracts; the 12 that declare env or secret keys were judged against their render and passed.

**The declared name is the consumer's key, not always the process's variable.** A component may remap: `registry/harbor` declares `EXTERNAL_URL` and wires `env EXT_ENDPOINT valueFrom configMapKeyRef harbor-runtime-config/EXTERNAL_URL`, because the chart bakes `EXT_ENDPOINT` into a ConfigMap the container also reads via `envFrom`. The duplicate rule is what keeps such a remap guarded — a second literal `EXT_ENDPOINT` fails the gate — but a component dropping the remap entry altogether is not detectable (§Named residuals). On the patch path the consumer sets the **process's** variable (`EXT_ENDPOINT` for harbor, not `EXTERNAL_URL`); harbor's README still documents the ConfigMap path only, which is a follow-up for that component, not for this change.

**Patching a key the artifact already wires through `valueFrom`.** A strategic-merge patch merges `env` entries by name and keeps the fields it does not mention, so adding `value:` to harbor's `EXT_ENDPOINT` yields an entry carrying both `value` and `valueFrom` — measured with kustomize 5.8.1 on the harbor render; the API server rejects such an EnvVar (an inference from its validation rule, not observed here). The patch clears the field explicitly: `{name: EXT_ENDPOINT, value: "https://…", valueFrom: null}` — measured: the merged entry carries `value` only.

**Why in `task ci`, not `validate:contract`.** The rule needs the render, and the `validate-contract` job renders nothing. The cost: `ci` now reads `customization.yaml`, which the note under `ci:artifact` deliberately kept out. It reads only the key names and `provided_refs`, and only for in-scope components under `CI_SCOPE_RANGE`, and a malformed contract cannot reach `main` because `validate-contract` is a required check — so the dependency this adds is the key list, not the contract's validity.

**Consumer delivery — two paths, both supported, precedence stated.**

| Path | How | Reaches every pod through a rollout? |
|---|---|---|
| env ConfigMap | the key in `provided_refs.env` | no — read at container start; an unplanned restart can bring one pod up on a newer value (the #803 class) |
| pod-template patch | a strategic-merge patch adding the key to the reading container's `env` with a `value:` literal | yes, except on an `OnDelete` workload |
| pod-template patch with `valueFrom` | as above, `valueFrom.configMapKeyRef` | no — resolved at container start, like the ConfigMap path |

A patched `env` entry silently beats the ConfigMap value for the same key; a consumer switching paths removes the ConfigMap entry. For a key several workloads read, the consumer patches each of them — an unpatched workload stays on the ConfigMap value or the placeholder default for as long as the patch set is incomplete.

**Recommended patch form — measured.** Probed with `kustomize build` (v5.8.1, the devbox pin) over the real `observability/loki` render, 2026-09-25:

| Patch | Result |
|---|---|
| no `target:`, body names `kind` + `metadata.name` + `metadata.namespace` of an existing StatefulSet | exit 0; the env entry lands, added to a container that had no `env:` |
| the same body without `metadata.namespace` | **exit 1** (`no matches for Id StatefulSet.v1.apps/loki.[noNs]`) — the namespace is part of the identity |
| the same body naming a StatefulSet that does not exist | **exit 1** — a renamed workload fails the build loudly |
| a `target: {kind, name}` selector that matches nothing | **exit 0, patch absent** — silent (upstream kustomize#4379, closed not-planned) |
| the body naming a container that does not exist | exit 0; the SMP **appends** an image-less container of that name |

So the recommended form is a strategic-merge patch with no `target:` selector whose body names the workload by kind, name and — when the rendered workload carries one — namespace, and the container by name. The last row is expected to fail at admission (a container without `image` is invalid) — an inference, not observed. **Scope of this evidence:** one namespaced render, measured with the devbox kustomize (`kustomize@latest` in `devbox.json`, resolved to 5.8.1 by `devbox.lock`), not with the Argo CD repo-server's bundled kustomize that consumers actually build with. The Argo-path probe did not run (the local cluster could not bind its host ports) and is an open verification item; until it runs, these rows are a measured expectation, not a guarantee of the consumer's build.

**Placeholder default syntax is per binary.** The expanders behind `-config.expand-env=true` differ. Measured 2026-08-31 against the shipped images:

| Placeholder | Variable | `grafana/loki:3.6.7` | `grafana/mimir:2.17.0` |
|---|---|---|---|
| `${VAR:1}` | `3` | `0` | `3` |
| `${VAR:1}` | unset | `0` | `1` |
| `${VAR:-1}` | `3` | `3` | `3` |
| `${VAR:-1}` | unset | `1` | `-1` |

Loki's expander is POSIX-style (`${VAR:N}` is a substring from offset N); Mimir implements its own `${VAR:default}`. Each silently misreads the other's form, and the wrong one passes every gate including `loki -verify-config`. A component adopting a placeholder measures the four cells against its own image; the gate checks only that the placeholder exists, never its default.

**Rejected alternatives.**

- *A baked `patchable_env` channel* (#838 as first filed): the artifact renders the key's default into the container `env` so a consumer patch replaces it. Rejected — that baked entry is exactly the silent override above for every consumer on the ConfigMap path, and moving an existing knob into it would override every consumer who had already set it.
- *A per-key `locations` list* (`target{kind,name}` + `container`) naming where each key is read. Rejected as unearned: one prospective adopter (#836), no ecosystem mechanism it would follow (kpt setters are deprecated, Helm `extraEnv` is ad hoc), and the rename risk it would guard is already loud on the consumer side with the recommended patch form. The patch target for a component is documented in its README.

**Parity.** No schema keyword changes, so decisions 1–4 above are untouched. Decision 5 gains one consumer-visible break: renaming or re-namespacing a workload or container that reads a declared key breaks consumers on the patch path — loudly for a renamed workload, via admission for a renamed container — and needs the same major bump and migration note as renaming the key.

## Named residuals

- **No render binding for the default.** `validate:env-keys` proves each optional key's placeholder exists; nothing proves the placeholder's default equals the declared `default`, or that the config file carrying it is the one the workload reads. The placeholder-default comparison is per binary (§No-shadowing), which is why it is not a repo-wide check; #802 tracks the render-vs-contract comparison.
- **CLI flags.** Loki and Mimir apply flags after the config file, so a flag for the same config field overrides both consumer paths. The gate does not parse `args`; review is the control.
- **Shadowing forms the gate does not model.** Each sets a declared variable with the gate green, and review is the control. A grep of the 12 declaring components' renders on introduction found no `kind: List`, no `ExternalSecret`, no `export NAME=` and no `MutatingWebhookConfiguration`; the CR-field shapes were not searched. The forms: a ConfigMap or Secret wrapped in a `kind: List`, or created at runtime by an operator (an `ExternalSecret`); an `export` in a shell `command`; a CR field that carries env as a map, as `NAME=value` strings, or under another key (`extraEnv`); env injected by a webhook. Nor does the gate know whether the reading binary expands placeholders at all (`-config.expand-env=true` present).
- **A remap entry removed.** For a component whose declared key reaches the process under another name through a `valueFrom` entry (harbor), deleting that entry leaves the chart-baked value in charge and the gate green — nothing in the contract names the process's variable.
- **Consumer patch coverage.** Nothing on the catalog side can see whether a consumer patched every workload that reads a key.
- **`group` is descriptive only.** Nothing validates that a consumer set every member of a group. It records a co-requirement for the reader; a consumer who sets a cache backend without its addresses gets whatever the workload does with that combination (for Mimir: a loud startup failure — but that is the workload's behaviour, not the contract's enforcement).
- **Version-skew cost is real.** Parity decision 3 means every consumer vendoring the schema must update it before adopting a component that carries `optional`. There is no forward-compatibility escape hatch short of opening the root, which would forfeit the closed-set property the contract relies on.
- **Channel classification is author-asserted.** No gate can tell whether a key genuinely has a working default; a component author could park a truly mandatory key under `optional` with a plausible-looking default. Review is the control.

## Action items

- Companion PR amending ADR-0024 in `talos-platform-docs` (the schema is that ADR's implementation), open before this change merges.
- ~~File the render-vs-contract placeholder-check follow-up issue.~~ Filed as #802.

## Consequences

Additive and repo-only (§No-shadowing added a render gate, its fixtures and schema-description text, likewise without touching a component): one schema block, ten fixtures, the two semantic checks and the fixture guard inside an existing task, plus documentation. No component file changes in this record's own change, so release-please cuts no tag and no OCI artifact is republished. Rollback is a single revert — **except** that it must be co-ordinated with any component that has adopted the block: reverting the schema alone makes that component's `customization.yaml` fail the required `validate-contract` check.

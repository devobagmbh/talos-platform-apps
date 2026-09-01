---
type: decision
title: "DR-0005 — Optional consumer-replaceable config files in the customization contract"
description: Extend the additive `optional` block of the customization contract with a `config_files` shape, so a component can declare a config file it ships with working content and the consumer replaces by kustomize patch; enforce the five rules JSON Schema cannot express in task validate:contract.
tags: [decision, contract, customization, schema, adr-0024, consumer-overlay]
timestamp: 2026-08-28
sources:
  - schemas/customization.schema.json
  - schemas/testdata/customization-optional-config-valid.yaml
  - Taskfile.yml
  - AGENTS.md
  - knowledge/decisions/DR-0004-optional-customization-keys.md
  - knowledge/reference/component-contract.md
---

# DR-0005 — Optional consumer-replaceable config files in the customization contract

- **Status:** Accepted for the repo-local scope (this schema shape and its five task-enforced rules). Like [DR-0004](DR-0004-optional-customization-keys.md), the platform-wide companion is `talos-platform-docs` **ADR-0037** — the ADR DR-0004 named, still `proposed` at the time of writing. This record does not ratify it, and nothing in the schema or the gate depends on the flip. See §Action items.
- **Date:** 2026-08-28
- **Issue:** [#831](https://github.com/devobagmbh/talos-platform-apps/issues/831), enabling [#832](https://github.com/devobagmbh/talos-platform-apps/issues/832)
- **Record class:** repo-local decision record (`knowledge/decisions/`), distinct from the platform-wide ADR series in `talos-platform-docs/adr/`.
- **Scope:** how a component declares a **config file** it ships with working content that a consumer may replace. Extends [DR-0004](DR-0004-optional-customization-keys.md) to a second of `required`'s four shapes. Does not change the OCI/build contract, the freeze line, `compatibility.yaml`, or any rendered artifact.

## Context

[DR-0004](DR-0004-optional-customization-keys.md) added the additive top-level `optional` block for one asymmetry: `required` says "the consumer MUST supply this or the workload does not function", which is the wrong shape for a knob that has a working baked default. It modelled the **env** shape only, and recorded why:

> A config-file / secret-key / selector optional channel has no user today, so its semantics would be unexercised: nothing would pin down what "an optional config file" means (mounted-but-empty? absent mount? default file baked in?). The block is `additionalProperties: false`, so adding a shape later is an explicit, reviewed schema change — which is the point.

That gate is now cleared for the config-file shape, and by two components rather than one:

- **`security/tetragon` already ships the shape undeclared.** Its `customization.yaml` sets `provided_refs.config: tetragon-config` with `required.config_files: []`, and its header comment states the semantics in prose: "the catalog ships usable stdout defaults; the consumer overrides via `provided_refs.config` only when tuning the event stream." That is precisely the state this record calls unacceptable — a consumer-facing override surface that exists only in prose, where nothing marks a rename as breaking. It is **not migrated here** (this change stays component-free); it is the channel's first migration target, tracked as [#833](https://github.com/devobagmbh/talos-platform-apps/issues/833).
- **[#832](https://github.com/devobagmbh/talos-platform-apps/issues/832) is the prospective adopter that pinned the semantics.** It makes `observability/kube-state-metrics` ship a CustomResourceState ConfigMap holding an empty-but-valid spec, which the exporter mounts and reads; a consumer replaces the content per-cluster to obtain `kube_customresource_*` series. What is verified today is render-level and source-level, not runtime, and it was verified against the UPSTREAM chart, not against the component in this tree — which still pins chart 7.5.1 and carries no `customResourceState` block at all. Concretely: `helm template` of `kube-state-metrics` 7.5.1 and 8.4.1 with `customResourceState.enabled=true` renders the ConfigMap, the read-only volume and mount, the `--custom-resource-state-config-file` flag and an `apiextensions.k8s.io/customresourcedefinitions` list/watch grant; and kube-state-metrics v2.20.0's `customresourcestate.FromConfig` iterates an empty `spec.resources` without erroring. The end-to-end claim ("the pod becomes ready on the empty spec and emits no custom-resource series") is an acceptance criterion of that issue, not an observation of this one.

So the answer to DR-0004's open question is **default file baked in**: the artifact ships the ref with working content, the workload already mounts it, and the consumer replaces the *content* — never the mount, and never the object.

The shape has no home in the contract as it stands:

- Under `required.config_files` it is a lie the schema happily accepts: it asserts the workload does not function without consumer input, which would make every existing consumer of `security/tetragon` non-conformant overnight, and `validate-contract` is a required status check.
- Undeclared, it is the tetragon state above.

## Decision

Add `config_files` as a second property of the existing `optional` object in `schemas/customization.schema.json`, closed at block and item level:

```yaml
provided_refs:
  config: kube-state-metrics-customresourcestate-config
optional:
  config_files:
    - path: /etc/customresourcestate/config.yaml
      ref: kube-state-metrics-customresourcestate-config
      key: config.yaml
      description: >-
        CustomResourceStateMetrics spec driving the kube_customresource_* series.
        Unset, the empty resource list emits no custom-resource series. Replacing it
        also obliges the consumer to grant list/watch on each apiGroup named.
        <how a replacement takes effect for this workload>
      default: |
        spec:
          resources: []
```

The channel boundary is unchanged from DR-0004 and is a definition, not a style preference:

- `required.config_files` — the consumer MUST author the file or the workload does not function. The ref may or may not be shipped; the *content* is not. `lifecycle/booter` is the worked example: it ships a ConfigMap whose body is `REPLACE-ME: "consumer-supplied proxyDHCP config"`, which is a placeholder, not working content — so `required` is correct there, and the two channels are empirically distinguishable in this repo rather than only definitionally.
- `optional.config_files` — the artifact ships the ref **with working content**; the consumer replaces that content only to change behaviour.

## The mechanism is a kustomize patch, never a write

The optional `ref` is inside the signed base and therefore Argo-managed. A consumer who edits that ConfigMap directly has the edit reconciled away. The only correct action is `source.kustomize.patches` on that object, the same ADR-0024 calibrated-friction path used for every other field of the base. This is stated in the schema's own field descriptions rather than left implicit, because the field vocabulary (`ref`, "the object the consumer acts on") is shared with `required.config_files`, where the ownership is the opposite and "the consumer creates it" *is* correct.

Whether a replacement then takes effect is per-workload, and the contract carries the answer in `description` rather than in a field of its own: a projected ConfigMap file updates on the kubelet sync period, but the process must re-read it, and the Helm-rendered `checksum/config` pod annotation was computed at catalog render time and does not change when a consumer patches the object. A boolean cannot carry that; prose can.

## `path` is a file path, and why its uniqueness spans both channels

`path` is the absolute path of the **file** the workload reads — the volume's mountPath plus the name the key projects to — matching what `required.config_files` already does in practice (`lifecycle/booter` declares `/etc/booter/booter.yaml`, not `/etc/booter`). This matters because a ConfigMap volume projects *every* key as its own file: two replaceable keys of one ConfigMap are two entries with two distinct file paths, not two entries fighting over one mountPath. Stating the field as "the mount path" would have made the ordinary multi-key shape unrepresentable and pushed authors toward `subPath` mounts, which kubelet never updates in place — the one mount kind that silently defeats replacement.

Uniqueness of `path` is checked across **both** channels together, not within the optional channel alone. The cross-channel case is the worst one, not an excluded one: when a consumer-authored file (`required`) and an artifact-baked file (`optional`) claim the same mount point, the two files have different *owners*, so "which one does the workload read" decides whether the consumer's own file is loaded at all.

**Not representable:** one `(ref, key)` mounted at two paths, e.g. into two containers. Declare the one the consumer's replacement is about. This is a deliberate narrowing, recorded here rather than discovered by the first author who hits it.

## Why `(ref, key)` is the identity, and why `default` is verbatim-only

An entry names two locations. `(ref, key)` is the object the **consumer's patch targets** — the ConfigMap name plus the data key — so it is the entry's identity for both the disjointness and the uniqueness rule. `path` is where the **workload reads** it, checked separately because the two fail differently (see §Rules below).

`default` is a **string carrying the baked content verbatim** — never a summary, and with no prose escape hatch for large content. The first draft of this record allowed "state the effective behaviour instead when the content is too large to inline". That was withdrawn under review: it makes the field bimodal with no discriminator, which forecloses the very follow-up this record names as the fix for its top residual. A render-vs-contract check ([#802](https://github.com/devobagmbh/talos-platform-apps/issues/802)) must compare `default` against the rendered ConfigMap's `data[key]`; against a bimodal field it cannot tell a byte mismatch (a defect) from a prose summary (intended), so it would ship with a permanent false-positive class or be dropped. A component whose baked content is genuinely too large gets a discriminated field of its own, as an explicit reviewed schema change — the same discipline that gated this shape.

## ConfigMap only — the Secret composition is refused mechanically

`required.config_files[].ref` may name a ConfigMap **or** a Secret. `optional.config_files[].ref` may name only a ConfigMap. The reason is compositional, not stylistic: this channel declares content the artifact **bakes**, and `default` records that content **verbatim**. A Secret ref would therefore instruct a component author to commit usable secret material into this repository — a direct collision with `AGENTS.md §Hard Constraints` ("No real secrets in the repo — not even in tests"). The `gitleaks` required check is an entropy/pattern scanner and would not flag a baked htpasswd, TLS or OIDC client config.

JSON Schema cannot see an object's kind, so the prohibition is enforced where it can be. The first draft did this with one negative rule — refuse a ref equal to `provided_refs.secret` (S6) — and adversarial review showed that closes nothing on its own: `provided_refs.secret` is an optional field the same author controls, so omitting it skips S6 entirely, and a skipped rule was indistinguishable from a clean evaluation. The rule that carries the weight is therefore the positive one: **S7 requires the ref to BE `provided_refs.config`**. An undeclared object can no longer enter the channel by omission; it takes an affirmative false declaration — naming a Secret as the component's config ref — which a reviewer can see in the diff. S6 stays alongside it so that the deliberate-evasion case gets its own message rather than reading as a typo.

The honest residual: no gate reads the render, so an author who declares a Secret's name under `provided_refs.config` still passes. S6+S7 raise the cost and record the intent; they do not close the class. A consumer-authored secret file remains a `required.config_files` / `required.secret_keys` concern.

## The five rules that live in the task

JSON Schema can express none of these, and each is a silent failure. All are asserted **over the real component files**, not only over fixtures.

- **S3** — `required.config_files` and `optional.config_files` are disjoint on the `(ref, key)` identity. A file either ships with working content or the consumer authors it; declaring both leaves the consumer unable to tell whether supplying nothing is legal.
- **S4** — within *each* channel, the `(ref, key)` identity is unique. Two entries for one file may declare different paths and different defaults, and nothing decides which holds. This covers `required` as well as `optional`: the older channel had no uniqueness rule at all, and forbidding a contradiction in the new channel while leaving it legal in the channel live components already populate is exactly the compounding asymmetry `rules/schema-contract-parity.md` exists to prevent.
- **S5** — `path` is unique across the union of both channels (see §`path` above). For that union to mean anything the two `path` fields must denote the same kind of value, so this change rewrites `required.config_files[].path` too — it still said "Mount path the workload reads the file from", the exact reading that would have made the union compare a directory against a file and miss the collision. The `pattern` and `maxLength` constraints are likewise applied to **both** channels, because both feed the `"<ref>|<key>"` identity the gate builds.
- **S6** — an `optional.config_files[].ref` is never `provided_refs.secret` (see §ConfigMap only above).
- **S7** — an `optional.config_files[].ref` IS `provided_refs.config`. The positive counterpart to S6, and the rule that actually closes the omission path (see §ConfigMap only above).

`semantic_check()` now distinguishes **exit 1 (a rule fired)** from **exit 2 (a rule could not be evaluated)**. Previously both returned 1, so a `yq` that was absent, the wrong flavour, or broken by a later edit would have made the fixture guard report every fixture as "correctly rejected" while binding nothing — the guard's entire job, silently inverted. This repo has a documented history of the two `yq` flavours colliding on `PATH`, and the per-channel uniqueness filter passes `--arg`, a jq-dialect flag mikefarah `yq` rejects outright (`Error: unknown flag: --arg`), so the failure mode was reachable rather than theoretical. It is the flag dialect that separates the two flavours, not the `\(…)` interpolation: mikefarah's `--string-interpolation` defaults to true and evaluates the identity filters cleanly. Verified by breaking a filter deliberately: the run now emits 8 `SEMANTIC FIXTURE UNEVALUATED` lines and zero false "correctly rejected" lines.

All three call sites — the real-component loop, the semantic-fixture guard and the positive-fixture guard — branch on all three states, and all three call `semantic_check` as `|| rc=$?`, never bare.

The reason is narrower than "any non-zero command aborts", and the first draft of this record got it wrong. go-task runs the script under mvdan/sh **with errexit in effect** — the script's own `set -uo pipefail` does not enable it — so a bare *simple command* exiting non-zero aborts the whole task, and a fixture that correctly fails the check is exactly that. Standard POSIX errexit exemptions still apply: a command inside an `&&`/`||` list or an `if` condition does not abort, which is why the bare AND-lists elsewhere in the Taskfile are safe. Verified with a throwaway task: a bare function call returning 1 killed the script, `false && { ... }` did not. The distinction matters because the wrong version of it invites a blanket `|| true` on gate members, which `AGENTS.md §Taskfile conventions` names as gate-blinding.

The same silent inversion exists one layer down, on the schema side: the negative-fixture loop reads a non-zero `check-jsonschema` exit as "correctly rejected", so anything that makes the command exit non-zero for a reason other than the schema greens the whole loop. Two probes close it, and they are complementary rather than redundant. A **validator-liveness probe** before the loop asserts the validator still ACCEPTS a known-good fixture — that covers an absent, broken or wrong-version validator. A **per-fixture parse probe** inside the loop asserts each fixture is readable and parses — that covers the case liveness cannot see, a fixture that is `chmod 000` or corrupted while the validator is perfectly healthy. Both were bound by observation: with the schema pointed at a missing file the run reports `VALIDATOR UNUSABLE`; with one fixture at mode `000` it reports `NEGATIVE FIXTURE UNREADABLE OR MALFORMED` and exits non-zero, where before it printed a green line.

## Two constraints that exist for the gate, not for Kubernetes

Two of the field constraints are stronger than Kubernetes alone would require,
and both were added after a cross-model review round found the gate evadable
without them.

**`path` must be canonical.** S5 compares raw strings, so `/etc/x/f.yaml` and
`/etc/x/./f.yaml` are two different keys in its `group_by` while naming one
file. The consumer-authored and artifact-baked entries could therefore collide
on a mount point and pass — exactly the case S5 spans both channels to catch.
The pattern now rejects an empty, `.` or `..` segment and a trailing slash, in
both channels, so the string comparison is sound rather than merely usual.

**`key` must not begin with two dots.** Kubernetes' `IsConfigMapKey` rejects
`.`, `..` and *any* key starting with `..` — the kubelet reserves that prefix
for a projected volume's own bookkeeping. The first pattern anchored on the two
exact names, so `..data` passed the contract and would have been refused by the
API server: a component could ship a declaration no cluster can honour.

A third, milder case is the same class: the constraints copied onto
`required.config_files` had no fixture of their own, because every negative
fixture exercised the optional channel. The `customization-required-*` fixtures
bind them, so the required side cannot silently regress while the optional side
stays green. `required.env_keys` and `required.secret_keys` gained `uniqueItems`
in the same pass — they hold plain strings, which S2 cannot see, so nothing
stopped one name appearing twice.

## Why only a second shape

`optional.secret_keys` and `optional.selector_crs` stay unbuilt on DR-0004's own reasoning: no component needs them, so nothing would pin down their semantics. This record is the demonstration that the reasoning holds — the config-file shape was built only once components defined what it means, and the definition it produced (default file baked in, replaced by patch, ConfigMap only) is not one that could have been guessed in advance. Because the `optional` block is `additionalProperties: false`, each further shape stays an explicit, reviewed schema change.

## Schema-contract parity (all five, per the harness meta-rule)

1. **Closed field set** — `additionalProperties: false` at the block and item level, as for `env_keys`. `path`, `ref` and `key` additionally carry `pattern`s (absolute-path; RFC 1123 DNS-subdomain; the ConfigMap data-key charset). Beyond charset hygiene these are load-bearing for the gate: it builds an entry identity as `"<ref>|<key>"`, so a `|` inside either field would make two distinct entries collide and produce a phantom duplicate. Kubernetes happens to exclude `|` from both, but the contract now enforces it rather than relying on that — in **both** channels, since both feed the identity function (the first draft hardened only the optional side, leaving the claim false of the required one).
2. **Duplicate entries** — a contradiction the schema cannot see (distinct array items), surfaced by S4 on the `(ref, key)` identity in both channels and by S5 on `path` across their union.
3. **Version skew** — there is still no version field, and the root is `additionalProperties: false`. A consumer holding a **vendored copy of the schema that predates the shape they encounter REJECTS** the `customization.yaml` carrying it; it does not ignore it. **`$id` is unchanged and is therefore NOT a staleness signal** — the only in-band signal is the validation error naming the unknown property. This is DR-0004's decision applied unchanged, and it now applies a second time: a consumer who updated their vendored schema for `optional.env_keys` must update it again for `optional.config_files`. Note the distribution path this actually runs over: `customization.yaml` is **not** inside the published OCI artifact — `task package` tars only `kustomization.yaml` and `manifest.yaml` — so a consumer reads both the contract and the schema from this repository at the tag they pin, and "vendoring" means copying the schema out of it. The schema's root description said the file "ships with the OCI artifact"; that was wrong and is corrected in this change.
4. **Untrusted-data marker** — not applicable; a repo-SOT trusted-data file changed only by reviewed PR.
5. **Per-field mutability** — entries are mutable in place by the component author, with **three breaking-and-silent exceptions**: renaming a shipped entry, removing it, and **changing its `default`**. The file case is quieter than the env case in two compounding ways. First, a renamed `ref`/`key` leaves the consumer's kustomize patch targeting an object the workload no longer reads, so the workload keeps running on the baked default with nothing signalling the loss. Second, the patch may not even fail: under `Prune=false`, or before GC runs, the *old* ConfigMap can still exist and accept the patch cleanly — so the consumer sees a green sync, an applied patch, and no effect, and diffing cluster state against expected state does not reveal it either. Changing a baked `default` changes runtime behaviour for every consumer who replaced nothing. All three are major-version changes with a migration note.

## Named residuals

- **No render binding.** Nothing compares a declared entry against the render. A declared `path`/`ref`/`key` that no rendered volume actually mounts passes green, so a one-character mismatch between the contract and `helm/*.yaml` produces a knob that silently does nothing. Same residual DR-0004 named for env placeholders, same most-likely defect class for any adopting component; tracked in [#802](https://github.com/devobagmbh/talos-platform-apps/issues/802). Keeping `default` verbatim-only (above) is what leaves that check buildable.
- **Shipped-content-usability is author-asserted, and this channel is cheaper to declare into.** No gate can tell whether the baked content is genuinely usable; an author could park a placeholder that makes the workload crash-loop under `optional` and the contract would validate. That is the same classification residual DR-0004 recorded for env defaults, but the incentive is sharper here: `required` makes existing consumers non-conformant against a required status check, so `optional` is the path of least resistance for a file that is genuinely mandatory. Review is the only control, and naming the residual is not itself a control.
- **Reload semantics are prose.** Whether a replacement takes effect without a pod restart lives in `description` and is not machine-checkable.
- **One `(ref, key)` at two paths is not representable** (see §`path`).
- **`group` is descriptive only.** Nothing validates that a consumer replaced every member of a group.
- **Version-skew cost recurs per shape.** See parity decision 3.
- **S6/S7 do not close the Secret class, they price it.** An author who declares a Secret's name as `provided_refs.config` passes both. Closing it needs the render, which no layer of this gate reads.
- **The gate is regex-dialect-dependent.** `pattern` is evaluated with ECMAScript semantics (check-jsonschema's default, via regress). Under `--regex-variant python`, `$` also matches before a trailing newline and a path carrying one would be accepted — a different string in S5's `group_by`, so a duplicate would stop colliding. The `-config-trailing-newline-path` fixture is the canary; nothing pins the variant.
- **Three schema keywords are unbound by symmetry.** `maxLength` on `key` in either channel mirrors the bound one on `ref`, and `uniqueItems` on `required.secret_keys` mirrors the bound one on `required.env_keys`. Stated in the task summary rather than bound by redundant fixtures.
- **A scoped run proves less than it looks.** `task validate:contract -- <component>` skips the whole fixture guard, so every red-green binding for S1-S7 goes unexercised. The task now says so on every scoped run, and CI runs the unscoped form.
- **The gate got slower.** Full-corpus wall time went from 24s to 39s (54s before a cheap probe that skips the four config-file rules for the 57 components declaring no `config_files` at all). It is a required status check, so the pressure this creates is toward per-component scoping — which is exactly the residual above.

## Action items

- Confirm whether `talos-platform-docs` **ADR-0037** — the companion DR-0004 named, `proposed` at that time — already covers the config-file shape. If it does, the companion obligation is that ADR flipping to `accepted`; if it does not, open the amendment PR **before this change merges**, mirroring DR-0004's own action item. Not resolvable from this repository.
- ~~File the `security/tetragon` migration follow-up (see §Context).~~ Filed as [#833](https://github.com/devobagmbh/talos-platform-apps/issues/833): declare its existing `tetragon-config` override surface under `optional.config_files`, or record why it does not qualify.

## Consequences

Additive and repo-only: one schema block, twenty-eight fixtures, five semantic rules (S3-S7), the alignment of the older `required.config_files` field definitions with them, and the fixture-guard entries inside an existing task, plus documentation. No component file changes in this record's own change, so release-please cuts no tag and no OCI artifact is republished. Rollback is a single revert — **except** that it must be co-ordinated with any component that has adopted the block: reverting the schema alone makes that component's `customization.yaml` fail the required `validate-contract` check, so this change and [#832](https://github.com/devobagmbh/talos-platform-apps/issues/832) revert together.

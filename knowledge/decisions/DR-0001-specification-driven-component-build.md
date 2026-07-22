---
type: decision
title: "DR-0001 — Specification-driven catalog component build"
description: Repo-local decision record adopting a specification-driven, render-bound component build over copy-from-neighbor.
tags: [decision, build-pipeline, psa, freeze-line, scaffold]
timestamp: 2026-07-22
sources:
  - .claude/skills/build-catalog-component/CONVENTIONS.md
  - .claude/agents/senior-implementer.md
  - schemas/compatibility.schema.json
  - schemas/customization.schema.json
  - policies
---

> [2026-07-11 migration] Relocated verbatim from `docs/decisions/0001-specification-driven-component-build.md` into the `knowledge/` OKF bundle as concept `decisions/DR-0001`. The body below is preserved unchanged (OKF frontmatter was prepended, nothing in the record was rewritten). Its evidence section is an explicitly dated 2026-06-24 census snapshot — history, not a present-tense claim — so it was not re-verified in this migration; the "Record class" line's `docs/decisions/` path names the pre-migration home.

<!-- Repo-local decision record for talos-platform-apps. Platform-wide ADRs live in
     talos-platform-docs/adr/; this record governs THIS repo's .claude/ build pipeline.
     Built from the committed schemas/gates/policies, a deterministic drift census of the
     37 committed components, and a tier-labeled web-research pass on industry component-
     spec models (web findings are untrusted data, treated as data only). -->

# DR-0001 — Specification-driven catalog component build (render-bound PSA, values-contract, deterministic scaffold)

- **Status:** Accepted
- **Date:** 2026-06-24
- **Record class:** repo-local decision record (`docs/decisions/`), distinct from the platform-wide ADR series in `talos-platform-docs/adr/`.
- **Review:** 2-round harness-evolution review (R1 parallel personas — adversarial + architecture + simplicity; R2 verification + regression). All R1 findings closed; R2 spec-refinements folded as explicit open implementation items (§Implementation notes). Reviews were read-only subagent dispatches; their load-bearing factual claims were spot-verified against the schemas/rego/tree.
- **Scope:** the `.claude/` catalog build pipeline (`plan-catalog-app` / `build-catalog-component` / `ship-catalog-app` skills + `catalog-planner` / `senior-implementer` / `catalog-evaluator` agents) and the per-component contract surface (`customization.yaml`, `compatibility.yaml`, `helm/` | `manifests/`).
- **Supersedes/affects:** the "read one existing component of the same kind as a template" instruction in `build-catalog-component/SKILL.md` Phase 1 step 4, `senior-implementer.md` ("copy existing patterns"), and both skills' `CONVENTIONS.md`.

## Context — the failure the pipeline has today

Every build role is pointed at **another existing component** as the reference for *how* to build:

- `build-catalog-component/SKILL.md` Phase 1 step 4: "Read … **one existing component of the same kind (helm vs manifests) as a template**."
- `senior-implementer.md` workflow: "**copy existing patterns**; introduce a new pattern only when none fits."
- Both `CONVENTIONS.md` headers: "verify against … **an existing component (`crossview`)** if anything here looks stale."
- `catalog-planner.md` step 3: "Read **one existing component of the same kind … as a shape reference**."

A neighbor component is a **sample of one possible output**, not a **specification**. As a reference it has three structural defects, each observed in this repo:

1. **No base case.** The first component of a new kind/sub-layer has no neighbor. The pipeline half-knows this — `build-catalog-component/SKILL.md` Phase 3 states "Building the **first component of a new sub-layer** is where this bites", and Phase 6.5 step 2 carries a "Template precondition (new sub-layer/component) … author it from an existing one". Both patch a symptom; neither supplies a base case. The first component is simultaneously the least-grounded (no neighbor) and the most-copied (it becomes everyone's template).
2. **Error propagation.** A defect in the copied neighbor is inherited, and the verify leg checks **shape, not correctness** (see the gate inventory below). A well-formed-but-wrong copy survives every gate. Documented instance: a hostPath node-agent labelled `enforce: baseline` passed render + conftest + 3-round review + evaluator and **merged**; only live ArgoCD admission caught it (the defect that motivated `conformance.pod_security` / PR #328). "HostPath Volumes" is a *Baseline* PSS control — baseline **and** restricted forbid it; only `privileged` admits it.
3. **Sample ≠ spec.** A sample encodes defects as authoritatively as correct decisions; nothing in the artifact distinguishes the two. Copying yields *correlation with the neighbor*, not *correctness*. It also defeats the judge≠builder independence the pipeline is built on: builder and copy-source derive from the same un-grounded origin.

## Evidence — axis inventory of the 37 committed components

Deterministic census (`git ls-files` + `grep`/`yq` over the committed tree, 2026-06-24). The pattern is the argument:

> **Axes with a deterministic gate are consistent (reproducible). Axes with no gate — or only a structural-shape gate — are spread/ad-hoc, and that is where the defects live.**

| Build axis | Industry anchor (Tier-1) | Ground-truth spec source | Deterministic gate today | Drift over 37 components |
|---|---|---|---|---|
| Image pinning | — | AGENTS Hard Constraints | ✅ `no_latest_image_tag.rego` (rendered images) | gated → consistent |
| YAML / core-K8s shape | — | — | ✅ `lint` + `lint:rendered` (kubeconform; **unknown CRDs skipped**) | gated → consistent |
| **Workload config / values** | Score `containers` · **Helm `values.schema.json`** | upstream chart `values` contract | ❌ **NONE** (no values schema, no values-intent check) | **ungated → copied per-component** |
| **PSA posture — label present+valid** | OAM Policy · K8s PSS | PSS standard | ✅ `pod_security_standards.rego` | 20 ship a Namespace, 17 don't |
| **PSA posture — workload conforms to level** | K8s PSS | PSS Baseline controls | ✅ `pod_security_conformance.rego` (`scan:psa-conformance`, `--combine`) — baseline/restricted structural forbids only; **privileged ungated; Restricted-additional deferred** | level spread: **10 restricted / 6 privileged / 3 baseline** |
| **PSA posture — *level choice* (too-loose)** | — | PSS controls over the *render* (type only cross-checks host-access) | ❌ **NONE** (evaluator judgment only) | **ungated** — the under-labelling direction |
| **Namespace ownership** (dedicated/shared/foreign) | OAM Scope | sole-claimant rule (CONVENTIONS) | ❌ **NONE** (cross-component name uniqueness "not yet mechanically enforced") | 20 / 17 split, chosen per-component |
| CRD-split (strict-B) | Helm `crds/` + ecosystem "separate chart" | ADR-0028 | ✅ `validate:crd-split` (correctness, **not completeness**) | **10 crds-dirs / 10 markers** (verified this session: `git grep -l '^crd-bearing: true'`) |
| **Freeze-line — structure** | kpt setters · Crossplane XRD | ADR-0024 + `customization.schema.json` | ✅ `validate:contract` (JSON-schema shape) | gated → consistent |
| **Freeze-line — semantics** (`required.*` ↔ rendered refs) | kpt setters · Crossplane XRD | ADR-0024 + rendered workload | ❌ **NONE** ("render-time checks … a follow-up", evaluator only) | **27 / 37 carry an all-empty (vacuous) freeze-line** |
| Capability mapping | Crossplane XRD/Composition · Backstage `providesApis` | ADR-0021 + `capability-index.yaml` | ◐ `validate:compatibility` (schema shape); index referential-integrity = build/evaluator, not a static gate | 16 mapped / 19 empty-array / **2 absent-key** (two encodings of "none") |
| Dependency surface | Score `resources` · Backstage `dependsOn`/`consumesApis` | ADR-0009 + graph | ◐ schema shape + ship/build merge-gate (existence at merge) | 13 / 37 have deps |
| Sync-wave | OAM Workflow-Step | bootstrap-ordering + strict-B | ◐ `validate:contract` (format `^-?[0-9]+$` only; **value-correctness ungated**) | 10×"-1", ~21×"0", 2×"10", 2×"20", 1×"30" (per-component inline rationale varies widely) |
| Version / provenance | Helm `version`+`appVersion` · kpt `upstreamLock` | `compatibility.schema.json` + SemVer tag | ✅ `lint:version` (sot parity: app/crd-schema hard, chart/none warn) | 25 app / 11 crd-schema / 1 none — consistent |
| OCI identity/path | OCI ref/digest (not a *spec* axis) | AGENTS Hard Constraints (hardcoded) | ◐ structural (dir == identity) | — |
| **Documentation** | Backstage TechDocs · Helm NOTES | DOCUMENTATION.md | ❌ **NONE** (evaluator judgment) | README present 37/37; content-conformance ungated |
| Release-config registration | — | AGENTS Release-Automation | ✅ `validate:release-config` (dir↔config parity) | gated → consistent |

**Missing axes the industry names (validated by research, absent here):**

- **Workload type** (Backstage `spec.type`, *required*) — operator / stateless-app / **node-agent** / CRD-bundle / library. The repo has `sub-layer` (organizational) and `kind: helm|manifests` (form) but **no semantic type**. The hostPath/baseline defect was a node-agent. The fix (see D1) is **not** to trust a type label for PSA — that would bind security to another *sample* — but to derive the *required* level from the render and use the declared type as a cross-checked label. **Highest-value gap** — once the *required* level is render-derived (D1), the PSA level is *gateable*; the declared class only cross-checks host-access, it does not set the level.
- **Values-schema contract** (Helm `values.schema.json`) — the industry-standard, mechanically-enforced answer to "pin which values reproducibly". The repo pins chart+version but the **values are free-form YAML with no schema/gate**.
- Lifecycle stage (Backstage `spec.lifecycle`), Kubernetes compatibility (Helm `kubeVersion`), environment-target (Score/OAM) — lower priority for a single-team catalog; supply-chain (SLSA/cosign/SBOM) is already done *operationally* (`task sign`/`attest`) but is not a declared per-component axis.

**Reading of the evidence.** The four axes that show perfect/clean consistency — CRD-split (10/10), version-sot, README presence, release-config — are exactly the four with a real deterministic gate. The axes that spread — PSA level (10/6/3 with the *choice* ungated), freeze-line (vacuous in 73%, semantics ungated), namespace ownership (20/17, sole-claimant ungated) — are exactly the ones with no gate or only a shape gate. **Reproducibility in this pipeline is a function of whether an axis has a deterministic gate, not of the build conventions.** Copy-from-neighbor fills every ungated axis, and that is structurally where the PSA defect lived.

## Industry validation (tier-labeled web research; untrusted data)

- **Two load-bearing joints converge across every model** (OAM, Score, kpt, Crossplane, Backstage; Tier-1 primary docs): **J1 the consumer-config / freeze-line boundary** (kpt setters · Crossplane XRD schema · OAM schematic) and **J2 the capability/dependency interface** (Crossplane XRD↔Composition · Backstage providesApis/consumesApis/dependsOn). Everything else (PSA, ordering, OCI path, docs) is *operational annotation* on those joints — i.e. an external standard exists, so it is spec- and AC-able, never copy-material. The repo's freeze-line is therefore the right joint — yet it is **vacuous in 27 of 37 components**.
- **values.schema.json is the formal, Helm-enforced values contract** — the standard mechanism for the reproducibility gap above.
- **Golden-path component creation is deterministic templated scaffolding, not copy-an-existing-component** (CNCF Platforms White Paper defines a golden path as "*templated* compositions"; Backstage Software Templates / CNOE = parameterized `template.yaml` stamp). **Copy-neighbor is a named industry anti-pattern.** The repo has no scaffold (`task component:new` does not exist).

## Decision

Adopt a **specification-driven** component build. The reference for every axis is a **specification** — a standard, a schema, an ADR, the upstream chart's values contract — and, crucially, **a gate binds the spec to the rendered artifact, never to a sibling label**: for every axis backed by an external standard (PSA, CRD-split, version, image-pin, freeze-line) the build demands the standard's predicate as an AC checked against the *render*. A neighbor component is demoted to a **format/idiom example only**, never a correctness reference. (This bind-to-the-render principle subsumes the first draft's separate D5.)

Four decisions follow.

- **D1 — Derive the *required* PSA level from the render; declare `workload_type` only as a label the gate cross-checks.** The root fix is **not** "declare a type and trust its PSA default" — binding security to a sibling label is itself a *sample*, the exact `sample ≠ spec` error this ADR diagnoses (a mislabelled `node-agent` would reproduce the original hostPath/baseline defect *behind an authoritative-looking field* — a worse failure surface, R1 team-red Scenario B). Instead:
  1. **Required level is render-derived** (mechanical — the rule AGENTS.md §ADR-Abdeckung already states): a workload using hostPath / host-namespaces / privileged / host-ports **forces `privileged`**; otherwise the strictest level its rendered `securityContext` satisfies. Extend the existing `scan:psa-conformance` (which gates only the *too-strict* direction) with the **`declared enforce == render-required`** check — closing the *too-loose / under-labelling* direction the inventory flagged as ungated.
  2. **`workload_type` is a declared, human-readable class** whose *only gated obligation* is that it **agrees with the render-derived class**. It is a cross-check + a scaffold/documentation default surface — never the source of truth for the level. A wrong type then **fails its agreement gate**, rather than silently driving a wrong default.
  - **Gated set is minimal** (per the simplicity review): the only distinction the gate needs *today* is **host-access vs not vs no-pod**. `no-pod` is **derived from the existing `crd-bearing` marker / absence of a workload** — *not* a new `crd-bundle`/`api-surface-only` type value (which would be a third encoding of a fact the repo already records). The finer classes (`operator` / `cluster-singleton` / `stateless-app` / `stateful-app`) are an **optional, explicitly *ungated*** sub-classification carrying *namespace/values-profile defaults* — deferred until a namespace or values gate exists to consume them, so no one reads a finer label as enforced.
  (Research basis: Tier-1 PSS blocking-controls ground the host-access derivation; Tier-2 OpenShift SCC named-class precedent corroborates; **no canonical industry workload-type taxonomy exists** — the finer set is *composed*, hence ungated-default and reviewed as a deliberate design artifact, never "derived from a standard".)
- **D2 — Add a per-component values contract, *with its gate named*.** Ship a `values.schema.json` per component AND wire its enforcement into the pipeline (`helm lint --strict` / schema-validation on `task render:one`, added to `task ci`) — a schema with no gate is just another convention, and §Evidence shows conventions do not hold here. **Honest scope (R1):** this gates the values *shape* (a regression violating the schema fails CI); it does **not** pin values *intent* (which knobs, to what). The intent for a new component is grounded in the upstream chart's own `values`/`values.schema.json` + the `workload_type` profile defaults — **reducing, not eliminating, the judgment**. (See §Consequences.)
- **D3 — Un-defer the freeze-line semantic check.** Make the ADR-0024 render-time check deterministic — each `required.*` entry maps to a real `secretKeyRef`/`envFrom`/`volumeMount` in the rendered workload, and hollow-vs-genuinely-empty is distinguished — and add it to `task ci`. **The exact gate is an open implementation item** (it needs the render + a structured walk of `required.*` against the rendered refs); this decision commits to *building* it, and if it cannot be specified cheaply it **drops to a tracked follow-up** rather than blocking the rest.
- **D4 — Replace copy-a-neighbor with a deterministic, validated scaffold.** `task component:new <sl>/<c> --type=<workload_type>` stamps the directory skeleton + all required `compatibility.yaml`/`customization.yaml` keys (and the type-derived namespace/PSA/values *defaults*) from a **closed-set, validated** `--type` — an unknown/misspelled type **errors, never falls through to a looser default** (R1: the scaffold stamps a security default, so an unvalidated `--type` is a footgun). **Altitude/ownership (binding):** `task component:new` is the *sole* scaffold generator; the build skills/agents **invoke** it, never replicate its output (deterministic-hierarchy: a CLI stamp, not LLM codegen). It removes the neighbor for the *structure* of the *first* of a kind; components 2..N start from the scaffold, not a sibling.
- **Scope normalization** (from the research): treat *source+pinning* and *versioning* as one **provenance** axis — **a relabel of the existing `compatibility.yaml` `version` block + `lint:version` gate, NOT a schema change**; demote *OCI path* from a build axis to a publishing concern; treat the catalog-metadata axes (ownership / lifecycle / k8s-compat / environment-target) as optional follow-ups (low marginal value for a single-team catalog).

### Implementation notes (open — named, not hand-waved; these gate D1/D2/D4)

- **Schema home + migration (the blocker the first draft omitted, R1-CRIT).** `workload_type` is a *declared component property* → its home is `compatibility.yaml`, i.e. a change to `compatibility.schema.json` (currently top-level `additionalProperties: false`; the closure is load-bearing per its own `reject-apis` threat-model). Add `workload_type` as an **optional** top-level key (NOT `required`), so the 37 existing files keep validating and are back-filled incrementally. Document the five `schema-contract-parity` decisions in the same PR: **closed-set enum** for the value; duplicate-key = corruption; no version field → harness-evolution migration; trusted repo-internal data (no sentinel); mutable-in-place. **D2's `values.schema.json` needs no closed-schema change** — it is a new file beside `helm/<c>.yaml`, a new file class, not a new key. So D1's `workload_type` is the *only* closed-schema change.
- **D1's PSA work is additive, not a rewrite.** Both existing gates (`pod_security_standards`, `pod_security_conformance`) key on the *shipped* Namespace label; D1 adds two comparators on top — `declared-enforce == render-required` and `workload_type ⇔ render-class` — leaving the existing rego intact.
- **`--combine` placement (R2).** The new comparators are per-component artifact-scoped, so they MUST live in the dedicated `scan:psa-conformance` (`conftest --combine`) task, NOT the whole-`policies/` `scan:conftest` run where the conformance package is inert (its own header warns that folding it into a non-combine run "turns the gate into a no-op while `conftest verify` stays green"). "Additive" = additive to the `--combine` task.
- **Reuse the rego's privileged-forcing control set (R2).** `render-required` MUST reuse the exact hostPath / host-namespaces / host-port / privileged control set `pod_security_conformance.rego` already enumerates — never a second, drifting encoding of "what forces privileged".
- **No-Namespace components are an explicit residual, not a blanket close (R2).** 17/37 ship no Namespace (consumer-owned; the rego exempts them by design), so `declared == render-required` has no `declared` operand there. The *too-loose* close therefore covers only the namespace-declaring components; a host-access workload shipping no Namespace stays the consumer's + the evaluator's responsibility (rego boundary #3). The gate does **not** force the 17 to declare a Namespace. (So §Consequences' "closes the too-loose direction" is scoped to namespace-declaring components — corrected here.)
- **`workload_type` value-set ownership (R2).** Own the valid values the **same way as `swap_class`/`role`** — a free string in the schema whose value-set lives in a catalog doc, NOT a JSON-Schema `enum` — matching the repo's deliberate "no enum, avoid drift" convention (`compatibility.schema.json` notes on `swap_class`/`role`). Membership is enforced by the scaffold's closed `--type` + an agreement check, not by the schema. (Re-label the parity decision: "closed-set, externally-owned" not "schema enum".)
- **`workload_type` ⇔ `crd-bearing` agreement; `no-pod` is derived, not declared (R2).** `no-pod` precisely means "ships no workload of the rego's closed gated kind-set" — `crd-bearing: true` is one *sufficient* case, not the definition (a pure-config / api-surface-only component like `lifecycle/providers` is no-pod without being crd-bearing). A `-crds` / no-gated-workload component carries no `workload_type`, or if back-filled it MUST equal the derived `no-pod`; a gate asserts `workload_type` does not contradict `crd-bearing`.

## Consequences

### Positive

- The first component of a new kind is buildable **without a neighbor for its *structure*** (scaffold + spec) — the base case exists.
- A **structural** defect can no longer propagate by copy: each *gated* axis is bound to the render via a spec, not a sample. (Values *intent* is mitigated — chart contract + type defaults — not eliminated; see below.)
- The reproducibility gap closes on the **gated** axes (render-derived PSA + the `declared == render` check, values-*shape* schema, freeze-line semantics) — the gated set grows to cover the axes that currently spread.
- Aligns with the industry norm (deterministic scaffold; spec-stable / implementation-swappable; **bind to the render, not a label**).

### Negative / cost

- Upfront work: the validated `component:new` scaffold, the `workload_type` schema change + the two new PSA comparators, per-component values schemas + their gate, and the freeze-line render-time gate.
- **`workload_type` is a derivation/cross-check hub** (PSA class + scaffold defaults) — a wrong classification can touch several outputs, the same single-point-of-failure shape this ADR criticizes in copy-neighbor (R1-architect). What de-risks it is exactly D1's render-binding: the type is *checked against the render*, so a wrong type fails its agreement gate instead of silently driving a wrong default.
- The existing 37 components are on the old pattern; migration is **incremental** (new/edited adopt; back-migration opportunistic). The spec is derived from the **external standard where one exists** (PSS, Helm values-schema, ADR-0024/0028) — but `workload_type` itself has **no canonical industry taxonomy** (the research found none): it is a *composed* set carrying the same base-case risk one level up, so it is reviewed as a deliberate design artifact, never presented as "derived from a standard". This is the load-bearing migration caveat.

### Honest limitations of this record

- Drift numbers are deterministic counts but **method-sensitive** — re-derive with a robust pattern before quoting. The namespace count was corrected mid-review from 19 to **20** (a single-space `^kind: Namespace` grep missed a namespace whose key carried extra whitespace; the robust `kind:[[:space:]]+Namespace` count = 20 declaring / 17 not; enforce-bearing = 21, itself method-sensitive). The three Namespace-family totals count subtly different predicates and are NOT interchangeable: **20** components declare a `kind: Namespace`; **21** carry a `pod-security.kubernetes.io/enforce` string somewhere (one applies the label without a matched `kind: Namespace` line); the PSA-level row's **10+6+3=19** counts only those whose declared-Namespace enforce level the level-census actually resolved. The thesis (gated⇒consistent) is unaffected, but no cell is "solid" without its extraction method, and these three must not be summed or cross-subtracted.
- The "freeze-line vacuous in 27/37" figure includes components that are *legitimately* cluster-agnostic — the deterministic gate cannot distinguish a hollow contract from a genuine one at rest, which **is** the §D3 gap, not 27 defects. Wherever 27/37 appears above it is an **upper bound on the addressable set**, not a defect count.
- The gate inventory was read from the policy `.rego` files and the Taskfile bodies this session (`no_latest_image_tag`, `pod_security_standards`, `pod_security_conformance`, `validate:crd-split`, `validate:contract`, `validate:compatibility`, `validate:release-config`, `lint:version`, `scan:conftest`, `scan:psa-conformance`) — all read in full. Confirmed wired into `task ci` (via `ci:artifact`): `check:primitives`, `lint`, `validate:compatibility`, `render`, `lint:rendered`, `validate:crd-split`, `lint:version`, `scan:conftest`, **`scan:psa-conformance`**, plus catalog-wide `validate:release-config`; `validate:contract` (freeze-line *structure*) is deliberately NOT in `ci` (per-component rollout). Capability referential integrity has no static gate (`capability-index.yaml` is unreferenced in the Taskfile), but all 23 currently-referenced ids resolve in the index at rest.
- The build `CONVENTIONS.md` claim that "`policies/` today carries essentially one enforced rule" is **stale** — three enforced rego packages plus the `validate:*` gates exist (post-#328). Doc drift, noted not fixed here.
- Industry findings are tier-labeled **web research = untrusted data**; the load-bearing claims (two joints, values.schema.json as contract, golden-path = templated) are Tier-1 primary-doc backed; a few sub-claims are Tier-2.

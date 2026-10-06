# Documentation Authoring Standard

The single source of truth for **how documentation is written in this repository** —
what a doc MUST contain, SHOULD contain, MAY contain, and MUST NOT contain. It is
written to be consumed by Claude Code and any other agentic tool as much as by human
maintainers; a reviewer (human or agent) judges every documentation change against it.

This standard is grounded in established conventions for exactly these file classes —
BCP 14 normative language, the Diátaxis documentation-type model, the helm-docs values
comment convention, and the Standard Readme section set — and records where the repo
consciously diverges (see §Grounding & conscious divergences).

`AGENTS.md` points here; the component-README *content checklist* is owned by
`.claude/skills/build-catalog-component/CONVENTIONS.md` and is referenced, not
duplicated, below.

## Normative language (BCP 14)

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document
are to be interpreted as described in [BCP 14](https://www.rfc-editor.org/info/bcp14)
([RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) + [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174))
when, and only when, they appear in ALL CAPITALS — per RFC 8174 the same words in
lowercase carry their ordinary English meaning and make no normative claim.

Gloss for the levels used below:

- **MUST** / **MUST NOT** — absolute requirement / prohibition. A reviewer blocks a doc
  that violates one.
- **SHOULD** / **SHOULD NOT** — strong default; deviation is permitted only with a
  reason a reviewer would accept, stated where the deviation lives. This is the level
  for "almost always do X."
- **MAY** (≡ **OPTIONAL**) — genuinely discretionary; either choice conforms.

A "lives elsewhere" note (e.g. "the install steps live in the consumer repo") is
descriptive scope guidance, not a normative level — it tells the author what belongs in
*another* artifact, not what this doc is forbidden to contain.

## Documentation types (Diátaxis)

[Diátaxis](https://diataxis.fr/) distinguishes four documentation modes by reader need —
*tutorial*, *how-to guide*, *reference*, and *explanation*. The catalog's documentation
is deliberately scoped to two of them:

- **Reference** is the dominant mode — factual, structured, consulted while working:
  what a component ships, its OCI path, its sync-wave, the obligations a consumer must
  satisfy. Reference stays terse and complete; it does not drift into explanation-essays
  — extended rationale is the bounded-explanation mode below, admitted only where a doc
  class declares it (the manifest-comment class does, for constraint rationale).
- **Explanation** is the bounded second mode — the "why" a future operator genuinely
  needs: a trade-off, a footgun rationale, a constraint's cause. Explanation is allowed
  but kept short and tied to a decision; long-form rationale lives in an ADR, linked by
  ID.
- **Tutorial** and **how-to guide** ("install component X on your cluster", step-by-step)
  are OUT OF SCOPE for this repo. The catalog has no live cluster; the consumer cluster
  repos own that path. The catalog documents *what it provides*, never *how a given
  consumer wires it up*.

Each doc class below names its dominant mode. The mode sets the bar for "what belongs":
reference must not drift into explanation-essays, and explanation must not expand into a
how-to the consumer repo owns.

## Scope rules (read first — these bound everything else)

- **SR1 — this standard governs PROSE, never functional Kubernetes values.** READMEs,
  doc text, and comments are in scope. A consumer token that is part of a *functional
  value* — a resource name (`vault-office-lab-remote`), a selector label
  (`io.cilium/lb-ipam-pool: seeder`), an image tag, a git URL a controller resolves
  (`tofuModuleSource`) — is configuration, not documentation. Abstracting it can break
  cert wiring, load-balancer IP selection, or a render. Functional values are out of
  scope here; they are governed by the existing "no cluster-specific values in the
  catalog" convention (`AGENTS.md`) and changed only by a deliberate, conservative
  config decision — never by a documentation edit.

- **SR2 — a functional resource NAME mentioned in prose stays as its literal
  identifier; only the per-consumer *attribution* is removed.** Writing
  `vault-office-lab-remote (Seeder)` → keep `vault-office-lab-remote` (a consumer's
  manifests reference that exact name; it is the identifier of a resource the catalog
  ships), drop the `(Seeder)` attribution. The literal name is not "naming a consumer".

- **SR3 — the test for the conservative path is "render-/signed-byte-affecting", not
  "prose vs value".** A comment inside a file under `sub-layers/*/components/*/manifests/`
  or a `helm/` values file contributes to the signed, rendered artifact's bytes — even
  editing a prose comment there forces a re-render and a re-sign. Such edits follow the
  conservative path: confirm the render byte-diff is intended and flag any re-sign.
  Doc-only files (`README.md`, this file) are not render-affecting and are edited freely.

- **SR4 — consumer obligation VARIANTS are documented abstractly by topology, never by
  consumer name.** A component legitimately supports more than one consumer *shape*.
  Document the shapes by their topology — "a consumer whose Vault is remote supplies a
  cross-cluster `ClusterSecretStore` with AppRole/JWT auth; a consumer whose Vault is
  in-cluster uses Kubernetes auth" — without stating which named cluster is which.

## What this standard governs

This standard governs the catalog's **published documentation** — the top, sub-layer,
and component READMEs and any prose that describes the catalog. Two clarifications on
the consumer rule:

- **Role vs instance.** The catalog → consumer *model* (the role) is always stated —
  the whole catalog rests on it. Only naming a *specific consumer instance* (a named
  cluster or repo) in catalog documentation is forbidden.
- **Internal harness primitives are out of scope.** Files under `.claude/` that must
  reference the real deployment topology to do their job (an operational-safety reviewer
  checking bootstrap order, a builder's tiered-bootstrap domain note) are operational
  reference, not catalog documentation, and may name the actual clusters.
- **Counterexamples are a bounded, enumerated teaching device — never a precedent.**
  A teaching standard must be able to cite the pattern it forbids, so this file quotes a
  small, fixed set of real tokens — `seeder` (SR1's LB-IPAM selector label) and
  `vault-office-lab-remote` / the `(Seeder)` attribution (SR2, SR4) — as functional-value
  examples or the *before* side of a transform. This carve-out covers ONLY these
  enumerated tokens in *this governance file*. It is never a licence to introduce a
  consumer name into catalog documentation, and "it is a counterexample" is not an
  accepted justification in a README or manifest review.

**Migration status:** the existing documentation corpus predates this standard and is
being brought into conformance across follow-up changes. Until a file is migrated its
non-conformance is known backlog — not a license to add new violations.

## Universal rules (every catalog documentation file)

- **Never name a specific consumer** (cluster, repo, or deployment) in documentation
  prose. State what *any* consumer must supply (its obligations), and where there is
  more than one, its obligation *variants* by topology (SR4).
- **No consumer URLs or consumer-specific domains in prose** — use placeholders
  (`<consumer-repo>`, `<consumer-domain>`).
- **English.** Every new or edited documentation file MUST be English (platform policy
  2026-06-03); existing German files are migrated when edited.
- **Reference ADRs and issues by their ID token** (`ADR-0024`, `#84`). The rationale
  itself lives in the ADR, not inline.

## Doc classes

### Top-level `README.md` — Diátaxis: reference + brief explanation

The MUST sections derive from the Standard Readme section set, mapped to a catalog
(divergences recorded in §Grounding).

- **MUST:** the repository's purpose (a short description + background — *what the
  catalog is*); the catalog → consumer *model* stated abstractly; the sub-layer list;
  **how to consume the catalog** (the Standard-Readme "Install/Usage" slot, reframed:
  the OCI path pattern, the tag scheme, how a consumer references a component); entry
  points to deeper docs.
- **SHOULD:** a table of contents when the file exceeds ~100 lines (Standard Readme
  threshold); a license pointer.
- **MAY:** a high-level capability/sub-layer overview table (columns describe *what the
  catalog provides*, never *who consumes it*).
- **MUST NOT:** a registry of named consumers (no `## Consumers`/"consumed by" section,
  no per-consumer column, no consumer repo links); cluster-specific values; a
  package-manager install badge or other library-distribution boilerplate (this is an
  OCI catalog, not a published library — see §Grounding).
- **Out of scope** *(non-normative — lives elsewhere)*: per-component detail (the component README owns it)
  and consumer-side installation specifics (the consumer repo owns them).

### Sub-layer `README.md` — Diátaxis: reference

- **MUST:** the sub-layer's purpose; the component list with sync-wave order; the ADRs
  it references.
- **SHOULD:** state the abstract consumer *obligations* and obligation *variants* (SR4)
  the sub-layer imposes, where they are not already on the component READMEs.
- **MAY:** a capability overview.
- **MUST NOT:** a per-consumer capability matrix; cross-cluster topology naming specific
  clusters; cluster-specific values.
- **Out of scope** *(non-normative — lives elsewhere)*: component-level content the component READMEs
  already carry — do not restate it.

### Component `README.md` — Diátaxis: reference + bounded explanation

The **required content checklist** (what ships, consumer obligations, sync-wave, OCI
path, related ADRs) is owned by
`.claude/skills/build-catalog-component/CONVENTIONS.md` — follow it there; it is not
duplicated here. The cross-cutting rules that apply on top:

- **MUST:** state consumer obligations abstractly, including secret-shape obligations
  (which keys / Vault-path patterns a consumer must supply) and obligation variants
  (SR4).
- **SHOULD:** include the short operational notes and trade-offs (the bounded
  *explanation* mode) where a future operator genuinely needs them.
- **MAY:** a longer rationale paragraph when a non-obvious decision warrants it and no
  ADR covers it.
- **MUST NOT:** name a specific consumer; carry cluster-specific values; expand into a
  consumer-side how-to (Diátaxis tutorial/how-to is the consumer repo's).
- **Out of scope** *(non-normative — lives elsewhere)*: ADR rationale (link by ID) and upstream chart
  documentation (link, do not reproduce).

### Manifest & config-file inline comments — Diátaxis: reference + bounded explanation

Comments in these files are the exception, not the norm: the YAML is the source and
states what a value is. A comment is admitted only when it passes the admission test
below; everything else is deleted or lives in the component README, the commit body or
an ADR.

(`helm/*.yaml`, `manifests/*.yaml`, `customization.yaml`, `compatibility.yaml`.) The
render inputs — `helm/*.yaml` and `manifests/*.yaml` — are render-/signed-byte-affecting,
so editing their comments follows the SR3 conservative path. `customization.yaml` and
`compatibility.yaml` are schema-validated config, not part of the signed render output,
so their comments are not signed-byte-affecting — but the admission test below applies to
all four file classes. Render-impact (SR3) governs only whether an *edit* takes the
conservative render-verify path, never whether a comment is admitted.

**Admitted value-description comments in `helm/*.yaml` follow the helm-docs convention —
and ONLY in `helm/*.yaml`.** A comment that passes the admission test and whose job is
to describe a values key SHOULD use the [helm-docs](https://github.com/norwoodj/helm-docs) `# --` annotation
(two dashes, a space, then the description) directly above the key, with `@default` and
an inline `(type)` where they help (the block below is illustrative — no such annotation
exists in the corpus yet):

```yaml
# -- (int) must stay 1: file storage is single-writer
replicaCount: 1
```

Scope and honest limits:

- **`helm/*.yaml` only.** Raw `manifests/*.yaml` are Kubernetes resources, not chart
  values — they have no values keys to annotate, so `# --` MUST NOT be used there; their
  comments follow the admission test below as plain prose.
- **Description format, not generation.** These files are upstream-chart *references*
  with a *partial* override set, not authored charts — helm-docs generates nothing here
  and would only ever see the overridden subset. The convention is adopted for a
  consistent, parseable, human-readable description format going forward, applied to new
  or edited value descriptions; it is not a mandated retrofit of the existing corpus
  (per §Migration status).
- **Disambiguation.** `# --` (a value description) is distinct from a `# --- … ---`
  section banner already used in some files (e.g. `harbor.yaml`) and from a comment that
  merely starts with a CLI flag (`# --enable-foo`). Do not read those as helm-docs
  annotations.

**Admission test.** Write the file without comments first, then admit a comment only
where a reader editing that file would otherwise do the wrong thing. An admitted comment
MUST state one of:

- a **constraint and the consequence of breaking it** — "cannot change to X because Y",
  the PSA level a workload forces, a render-time-only setting a consumer patch cannot
  reach; a one-line "this value is a placeholder the consumer replaces" is such a
  field-level constraint, not an obligation narrative;
- a **coupling invisible from this file** (e.g. a label that must match a selector
  defined in another manifest);
- a **rejected alternative** where the obvious edit is the wrong one, including an
  intentional absence ("X stays unset because Y"), written as prose, never as
  commented-out config;
- a **form a tool mandates** — a yamllint directive, a schema modeline.

An admitted comment MUST be stated in the fewest words that carry the fact, in the
present tense; content that needs more than about three lines belongs in the component
README, the commit body or an ADR. It MAY carry a single ADR ID as a pointer. A
constraint that holds identically in sibling files MAY be stated, in one line, in each.

The decisive question for a doubtful comment is **"would an editor of this file break
something — silently, or only later in a consumer's cluster — without it?"** If so it is
admitted, even when the README or an ADR also carries the rationale: it then shrinks to
the one-line guard plus a pointer. Removing an admitted constraint is the same defect as
adding narration. A comment that matches both an admitted category and a residue rule
below is admitted only as that one-line guard; the rest is residue.

A guard is redundant only when a gate **fails on the broken edit itself**: a deletion
that relies on one MUST name the gate and the failing edit in the commit body, and only
a gate that blocks a merge (a required check or `task ci`) counts — an advisory gate, or
one that covers the same area without failing on the edit, does not. `scan:psa-conformance`,
for instance, fails a level that is too strict for the workload, not one that is too lax.

Open work is tracked in an issue and marked at the value by a single line,
`# TODO(#123): <what is open>`, with no narrative; the line MUST be deleted when the
issue closes. A pending-verification marker (`>>> VERIFY …`) MUST NOT be dropped
silently: delete it only once the verification is done, or replace it with such a
`TODO`.

Residue MUST NOT exist — delete it, or move the content to the component README, the
commit body or an ADR:

- **restating** what the key, value or name already says (this includes a `# --`
  description that adds nothing: the helm-docs form never admits a comment by itself);
- **history and process** — who changed it or when, review or PR narration, "verified on
  <date>";
- rationale **duplicated from the README or an ADR** beyond the one-line guard and
  pointer;
- the same **multi-line block repeated** across sibling files;
- **consumer obligations and operating procedure**: delete one only when the component
  README already states it, otherwise move it there in the same change (the secret keys
  a consumer supplies are declared in `customization.yaml` `required.secret_keys`, not
  narrated);
- **commented-out config**, **section banners**, and a **TODO** without an issue number;
- architecture essays, roadmap / deferred-work narrative, capability-edge prose.

The test governs every comment a change adds or edits, and every comment attached to a
line the change edits — a changed value and the comment guarding it are one unit, and a
reviewer MUST block a change that leaves such a comment false. A pure move or re-indent
touches no comment. All other existing comments are backlog (§Migration status); a
reviewer MUST NOT block a change for them.

## Enforcement

This standard is enforced **semantically**, by review — its subject is prose, which a
literal pattern-match cannot judge (a paraphrased consumer, narrative-vs-essential, or
section completeness is a judgment call). The BCP-14 keywords make each rule a
checkable assertion a reviewer can apply consistently. The repo's reviewers
(`.claude/agents/staff-reviewer.md` as the primary gate, `catalog-evaluator` and the
`build-catalog-component` review phase for component builds) check documentation
changes for conformance by **pointing to this file as the single oracle** — they do not
restate its rules. Editing those reviewer bodies is harness-evolution and follows the
2-round review discipline in `.claude/rules/review-convergence.md`. Changes to this
standard itself are governance changes — review them with that same discipline.

**Known limitation:** there is no mechanical gate proving zero consumer names remain —
acceptance is reviewer-attested. (A literal-string CI tripwire was considered and
declined: it covers only exact known strings, not the semantic rule, and a paraphrase
evades it.)

## Grounding & conscious divergences

This standard adopts established conventions for these file classes and diverges only
where the repo's nature (an internal OCI catalog of chart references, not a published
library or an authored chart) makes a convention inapplicable:

- **BCP 14 (RFC 2119 + RFC 8174)** — adopted wholesale for normative keywords. This
  replaces the earlier ad-hoc `MUST/MAY/MUST-NOT/NEED-NOT` set: `NEED NOT` is not a
  BCP-14 keyword (its intent — "belongs in another artifact" — is now an explicit
  *Out of scope* note), and `SHOULD/SHOULD NOT` (absent before) is added as the level
  for strong-default-with-stated-exception guidance.
- **Diátaxis** — adopted as the doc-type lens. Reference and (bounded) explanation are
  in scope; *tutorial* and *how-to guide* are deliberately out of scope — the consumer
  cluster repos own the live-cluster, step-by-step path.
- **helm-docs `# --` convention** — adopted as the form of an admitted value comment in
  `helm/*.yaml` only (raw `manifests/*.yaml` excluded). **Divergence:** the repo ships
  chart *references* with a *partial* override set, not authored charts, so helm-docs
  generates nothing here and would only see the overridden subset — the convention is
  adopted as a consistent description format going forward (new/edited values), not for
  generation, and is not yet present in the corpus (a green-field convention,
  disambiguated from the `# --- … ---` banners some files already use).
- **Standard Readme** — the top-README MUST/SHOULD sections derive from its section set
  (purpose/background, consume-instructions ≈ Install/Usage, TOC threshold, license).
  **Divergence:** library-distribution boilerplate (package-manager install badge,
  npm-centric assumptions) is dropped — a consumer references signed OCI artifacts by
  tag, it does not install a package; "Contributing" lives in `AGENTS.md`, not a README
  section.
- **Artifact Hub annotations** — noted and out of scope: OCI publishing metadata
  (`Chart.yaml` annotations) is a *publishing* concern owned by the pipeline and the OCI
  tag scheme, not documentation prose this standard governs.

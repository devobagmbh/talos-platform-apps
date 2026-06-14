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
  class declares it (the manifest-comment class does, for footgun/PSA rationale).
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

Predominantly reference (what a value is), with the bounded explanation a future editor
needs — a footgun's cause, a PSA value's rationale. That bounded explanation is exactly
the MUST-PRESERVE content below; what stays out is unbounded narrative (the MUST NOT).

(`helm/*.yaml`, `manifests/*.yaml`, `customization.yaml`, `compatibility.yaml`.) The
render inputs — `helm/*.yaml` and `manifests/*.yaml` — are render-/signed-byte-affecting,
so editing their comments follows the SR3 conservative path. `customization.yaml` and
`compatibility.yaml` are schema-validated config, not part of the signed render output,
so their comments are not signed-byte-affecting — but the comment-disposition policy
below applies to all four file classes. Render-impact (SR3) governs only whether an
*edit* takes the conservative render-verify path, never whether a comment is preserved —
a secret-shape obligation in `customization.yaml` is MUST-PRESERVE regardless.

**Value-description comments in `helm/*.yaml` follow the helm-docs convention — and
ONLY in `helm/*.yaml`.** A comment whose job is to describe *what a values key is*
SHOULD use the [helm-docs](https://github.com/norwoodj/helm-docs) `# --` annotation
(two dashes, a space, then the description) directly above the key, with `@default` and
an inline `(type)` where they help (the block below is illustrative — no such annotation
exists in the corpus yet):

```yaml
# -- (int) controller replica count
replicaCount: 1
```

Scope and honest limits:

- **`helm/*.yaml` only.** Raw `manifests/*.yaml` are Kubernetes resources, not chart
  values — they have no values keys to annotate, so `# --` MUST NOT be used there; their
  comments follow the disposition policy below as plain prose.
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

**The four dispositions** govern every comment in all four file classes. The decisive
question is **"would a future editor cause a silent failure without seeing this AT the
value?"** — not comment length. The `# --` description form does NOT replace the
MUST-PRESERVE class: a value description and a footgun guard are distinct *dispositions*,
not necessarily distinct *comments* — they MAY share one comment block (the `# --`
portion describes the key, the footgun portion is MUST-PRESERVE), and MUST-PRESERVE
content is never dropped even when fused with a description.

- **MUST (inline):** a non-obvious value or constraint, explained at the point it
  applies (in `helm/*.yaml`, value descriptions use the `# --` form above).
- **MUST-PRESERVE (inline, never relocated):** the comment classes whose removal causes
  a silent failure for a later editor —
  - *operator signals*: pending-verification markers (`>>> VERIFY …`), placeholder
    notices (`PLACEHOLDER` / `REPLACE-ME`), and intentional-absence records
    ("X is NOT shipped because Y");
  - *footgun guards*: "cannot change to X because Y" constraints (e.g. "not relaxable
    to baseline/restricted");
  - *security / PSA rationale* justifying a `pod-security.kubernetes.io/enforce` value;
  - *consumer secret-shape obligations* (which secret keys / Vault paths the consumer
    must supply).

  These stay inline even when multi-line or prose-shaped; when a comment could be read
  as either MUST-PRESERVE or MUST NOT, default to MUST-PRESERVE. (A *specific* per-file
  inventory of such comments belongs in the cleanup task's working notes, not in this
  durable standard — line numbers rot.)
- **MAY:** a single ADR/issue reference token.
- **MUST NOT (move to the component README or the ADR):** architecture essays,
  roadmap / deferred-work narrative, capability-edge prose, multi-paragraph history.
- **Out of scope** *(non-normative — lives elsewhere)*: restating what the YAML key already says — omit it.

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
- **helm-docs `# --` convention** — adopted as the value-description comment form in
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

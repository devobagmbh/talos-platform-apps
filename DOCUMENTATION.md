# Documentation Authoring Standard

The single source of truth for **how documentation is written in this repository** —
what a doc MUST contain, MAY contain, MUST NOT contain, and NEED NOT contain. It is
written to be consumed by Claude Code and any other agentic tool as much as by human
maintainers; a reviewer (human or agent) judges every documentation change against it.

`AGENTS.md` points here; the component-README *content checklist* is owned by
`.claude/skills/build-catalog-component/CONVENTIONS.md` and is referenced, not
duplicated, below.

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
- **Counterexamples are not violations.** This standard may quote a real attributed
  instance — e.g. the *before* side of a before→after transform (SR2's
  `vault-office-lab-remote (Seeder)`) — to teach a rule unambiguously. A standard must be
  able to cite the pattern it removes, exactly as a teaching doc names a forbidden
  pattern; the quoted token is the thing being *removed*, not the catalog naming a consumer.

**Migration status:** the existing documentation corpus predates this standard and is
being brought into conformance across follow-up changes. Until a file is migrated its
non-conformance is known backlog — not a license to add new violations.

## Universal rules (every catalog documentation file)

- **Never name a specific consumer** (cluster, repo, or deployment) in documentation
  prose. State what *any* consumer must supply (its obligations), and where there is
  more than one, its obligation *variants* by topology (SR4).
- **No consumer URLs or consumer-specific domains in prose** — use placeholders
  (`<consumer-repo>`, `<consumer-domain>`).
- **English.** Every new or edited documentation file is English (platform policy
  2026-06-03); existing German files are migrated when edited.
- **Reference ADRs and issues by their ID token** (`ADR-0024`, `#84`). The rationale
  itself lives in the ADR, not inline.

## Doc classes

### Top-level `README.md`

- **MUST:** the repository's purpose; the catalog → consumer *model* stated abstractly;
  the sub-layer list; how to consume the catalog (OCI path pattern, tag scheme); entry
  points to deeper docs.
- **MAY:** a high-level capability/sub-layer overview table (columns describe *what the
  catalog provides*, never *who consumes it*).
- **MUST NOT:** a registry of named consumers (no `## Konsumenten`/"consumed by"
  section, no per-consumer column, no consumer repo links); cluster-specific values.
- **NEED NOT:** per-component detail (that lives in the component README) or
  installation specifics that belong to a consumer repo.

### Sub-layer `README.md`

- **MUST:** the sub-layer's purpose; the component list with sync-wave order; the ADRs
  it references.
- **MAY:** abstract consumer *obligations* and obligation *variants* (SR4) the sub-layer
  imposes; a capability overview.
- **MUST NOT:** a per-consumer capability matrix; cross-cluster topology naming
  specific clusters; cluster-specific values.
- **NEED NOT:** restate component-level content the component READMEs already carry.

### Component `README.md`

The **required content checklist** (what ships, consumer obligations, sync-wave, OCI
path, related ADRs) is owned by
`.claude/skills/build-catalog-component/CONVENTIONS.md` — follow it there; it is not
duplicated here. The cross-cutting rules that apply on top:

- **MUST:** state consumer obligations abstractly, including secret-shape obligations
  (which keys / Vault-path patterns a consumer must supply) and obligation variants
  (SR4).
- **MAY:** operational notes, trade-offs, and a short rationale where a future operator
  genuinely needs them.
- **MUST NOT:** name a specific consumer; carry cluster-specific values.
- **NEED NOT:** reproduce ADR rationale (link by ID) or upstream chart documentation.

### Manifest & config-file inline comments

(`helm/*.yaml`, `manifests/*.yaml`, `customization.yaml`, `compatibility.yaml`.) The
render inputs — `helm/*.yaml` and `manifests/*.yaml` — are render-/signed-byte-affecting,
so editing their comments follows the SR3 conservative path. `customization.yaml` and
`compatibility.yaml` are schema-validated config, not part of the signed render output,
so their comments are not signed-byte-affecting — but the full four-disposition comment
policy (MUST-PRESERVE included) applies to all four file classes. Render-impact (SR3)
governs only whether an *edit* takes the conservative render-verify path, never whether a
comment is preserved — a secret-shape obligation in `customization.yaml` is MUST-PRESERVE
regardless.

Four dispositions. The decisive question is **"would a future editor cause a silent
failure without seeing this AT the value?"** — not comment length.

- **MUST (inline):** a non-obvious value or constraint, explained at the point it
  applies.
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
  as either MUST-PRESERVE or MUST-NOT, default to MUST-PRESERVE. (A *specific* per-file
  inventory of such comments belongs in the cleanup task's working notes, not in this
  durable standard — line numbers rot.)
- **MAY:** a single ADR/issue reference token.
- **MUST NOT (move to the component README or the ADR):** architecture essays,
  roadmap / deferred-work narrative, capability-edge prose, multi-paragraph history.
- **NEED NOT:** a comment that restates what the YAML key already says.

## Enforcement

This standard is enforced **semantically**, by review — its subject is prose, which a
literal pattern-match cannot judge (a paraphrased consumer, narrative-vs-essential, or
section completeness is a judgment call). The repo's reviewers
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

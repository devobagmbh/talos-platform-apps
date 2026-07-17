# `talos-platform-apps` — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

This repo follows the **mcp-server style**: its own `.claude/` directory with subagents, hooks, and settings. Unlike `talos-platform-base` (which waits on the `kube-agent-harness` plugin), we ship the primitives in-tree so the repo is self-contained from the start.

### Hooks

- `.claude/hooks/require-review.sh` — PreToolUse gate for `Bash` commits. **Currently inactive** (not bound in `settings.json`). With two maintainers (Thomas + Robert, both in CODEOWNERS) and M2 reached, fail-closed review enforcement is warranted; the hook binds in the **final** reactivation stage, after the `.claude/reviews/` emission substrate it depends on is wired — binding it before that substrate exists would block every commit. Until then the script is the contract the review agents emit against.
- `.claude/hooks/pre-commit` — native Git pre-commit path that validates **review artifacts** (`review.md` `verdict` + implementer≠reviewer role separation). Inactive (not installed); bound in the same final reactivation stage as `require-review.sh`, after the emission substrate lands.
- **`lefthook.yml`** — the **active** Git-hook orchestrator (a command-runner over devbox-provided binaries + `task` targets; no managed toolchain, so `devbox.json` stays the single tool-version SoT). pre-commit jobs: single-component scope, signing-config, `task lint`, gitleaks, whitespace/conflicts, no-rendered, no-makefile, no-large-files; commit-msg job: Conventional Commit. Check logic lives in the Taskfile (`lint:commit-msg`, `lint:commit-scope`, `lint:signing-config`). The `signing-config` job fails fast when commit signing is not configured locally (`main` enforces `required_signatures`; an unsigned commit makes the PR BLOCKED) — see `README.md` § Commit signing. Replaces the former `.pre-commit-config.yaml`. Install per clone: `lefthook install`. Note: git-emitting jobs use `git --no-pager` (lefthook runs jobs in a PTY → a bare `git diff` would launch the pager and hang). See ADR-0032.

### Subagents — 8 impl/review roles + 1 build verifier + 2 plan-phase roles

Tiered-review model, adapted from `talos-mcp-server`. At the 2026-05-26 reduction (Bobby's bus-factor critique) the apparatus was trimmed to 5 impl/review roles while M2 was pending; **M2 is now reached (2026-06)** and the escalation reviewers are restored — `principal-architect-reviewer`, `provenance-reviewer`, `compatibility-reviewer` are back. The fourth parked role, `senior-plan-reviewer`, is **not** restored: `plan-reviewer` subsumes it (same tools/model/verdict, dual conformance/adversarial stance), so a separate one would be an A5 vanity split. `catalog-evaluator` stays a separate build-time verifier (not a review role): judge-builder separation, since an agent that builds *and* verifies its own work is the documented self-verification/self-preference failure (MAST FC3). The plan phase is a separate axis with the `catalog-planner`/`plan-reviewer` pair (below).

Available in `.claude/agents/`:

- `senior-implementer` — writes code/manifests/Helm values; has write+edit+bash
- `catalog-evaluator` — independent build-time acceptance verifier (deterministic gate + semantic ACs, tamper/chart-ref check); read+bash, no write/edit; never the same context that built it
- `staff-reviewer` — primary gate before commits, triages to specialists when needed
- `security-reviewer` — Vault/SOPS/cosign/SBOM/RBAC/policies
- `operational-safety-reviewer` — bootstrap ordering, DR risks, backup paths
- `principal-architect-reviewer` — architecture escalation: sub-layer boundaries, OCI-layer model (ADR-0009), ADR obligation, API-surface shape
- `provenance-reviewer` — supply-chain escalation: cosign keyless identity, SLSA, SBOM, chart/image source trust
- `compatibility-reviewer` — compatibility escalation: compatibility.yaml, chart/CRD bumps, consumer-breaking value changes
- `researcher` — research in the base/other repos, findings synthesis

Plan-phase pair (judge-builder separation, orchestrated by the `plan-catalog-app` skill):

- `catalog-planner` — writes the catalog-app plan (components, dependency graph + build_order, capability mapping, freeze-line sketch, testable ACs); write scope is `.work/plan/` only, no verdict (builder class)
- `plan-reviewer` — read-only plan reviewer, canonical verdict enum; one definition serves both the conformance and the adversarial persona (stance per brief)

Restored at M2 (2026-06): `principal-architect-reviewer`, `provenance-reviewer`, `compatibility-reviewer` (the three escalation-domain reviewers — architecture / provenance / compatibility). `senior-plan-reviewer` is **not** restored — `plan-reviewer` subsumes it (A5).

### Skills + Workflows

In-tree Claude Code primitives for the catalog build (issues #17–#61), following current Claude Code + LLM best practices (deterministic gate first, LLM judge only for the semantics; builder ≠ verifier; parallel personas instead of sequential debate):

- **`/ship-catalog-app <app>`** (`.claude/skills/ship-catalog-app/`) — **end-to-end orchestrator** for the full plan→approve→build arc of ONE catalog app in a single session. A pure orchestration layer: it calls the two skills below and does NOT duplicate their logic/conventions. Three invariants: (1) a mandatory human **plan-approval gate** between the plan and N PRs (headless → stop-after-plan); (2) **merge gate mechanically pre-classified, build skill as backstop** — a component whose `external_dependencies` are not merged to `main` is `awaiting-merge` and is not attempted; ship's conservative pre-check is only a dispatch-saving optimization ahead of this backstop — the sole guarantee is **no wrong build** (the authoritative build check stops every inadmissible component); both misclassifications are harmless (over-admission → wasted dispatch; false-stall when a dependency is merged externally after the fetch → transient, resolved by a re-run); (3) **re-run-resumable** from the observed git status, no ship-state file. Spec/DRY source: the SKILL.md + the two sub-skills (no separate CONVENTIONS.md).
- **`/plan-catalog-app <app>`** (`.claude/skills/plan-catalog-app/`) — plans ONE catalog app (1-N components) through a converging plan→review→revise loop: `catalog-planner` writes the plan, `plan-reviewer` reviews it in parallel as two personas (conformance + adversarial, cross-model where possible), finding ledger, hard round cap 3, explicit termination (converges or surfaces residuals, never loops). Output: a finding-free plan under `.work/plan/<app>/` that `/build-catalog-component` consumes per component. Planner ≠ reviewer (judge-builder separation). Spec/DRY source: `CONVENTIONS.md` in the skill directory.
- **`/build-catalog-component <sub-layer>/<component>`** (`.claude/skills/build-catalog-component/`) — builds ONE component through builder→verifier→reviewer in separate contexts; fix-loop cap 2; branch + PR, never auto-merge. **Per-session unit for parallel independent sessions**: Phase 1 calls `task worktree:create -- <sub-layer>/<component>` and works in its own git worktree (`.claude/worktrees/<slug>`) — multiple sessions thus run in parallel on ONE clone (cross-session-safe `mkdir` lock; branch name = claim, a second session on the same component fails hard). Spec/DRY source: `CONVENTIONS.md` in the skill directory.
- **`catalog-fleet`** (`.claude/workflows/catalog-fleet.js`) — **optional single-operator fan-out**: ONE session fans out N components (build→verify→review as a pipeline, a worktree per build via `task worktree:create`, schema-validated output, consolidated report). **The primary path for parallelism is independent sessions + the skill (above)** — the workflow is only for single-operator mass fan-out. Shared-file integration (capability-index, sub-layer aggregates) + PR stay serialized/human. Requires explicit opt-in (Workflow tool).

### Rules (repo-local, path-scoped)

`.claude/rules/*.md` carry the **main-session editor discipline** for
primitive edits — repo-local and self-contained, loaded via `paths:` frontmatter
when you read/edit a matching file (a documented Claude Code mechanism,
`memory.md` § "Organize rules with `.claude/rules/`"). They replace any dependency
on a global user config:

- `agent-conventions.md` (`paths: .claude/agents/**`) — A1 (no peer names in the
  body), A3 (description = routing surface), verdict-schema parity,
  injection-hardening inline, judge≠builder, evidence discipline.
- `review-convergence.md` (`paths: .claude/{skills,agents,hooks,workflows}/**`) —
  converging review loop (parallel cross-model personas instead of sequential
  rounds, finding ledger, hard round cap, explicit termination), escalation-on-
  critical, harness-evolution 2-round minimum.
- `self-containment.md` (`paths: .claude/**`) — no reference to a personal
  global Claude config; subagent discipline lives **inline** in the agent body (subagents
  do not load these rules); `task check:primitives` is the deterministic gate.

**Important:** subagents do NOT load these rules (isolated context) — runtime-binding
discipline lives inline in each agent body, the rules only remind the editor.

### Settings

`.claude/settings.json` contains:

- **Permissions allowlist** — reduces permission prompts (Bash, Read, Edit, Write, Glob, Grep, Agent + selected `mcp__github__*` tools).
- **No hook bindings active** — see the "Hooks" section above.

### Host-permission interaction & shell

- **`sub-layers/secrets/` is secret-management *tooling*, not secret material.**
  Its components (external-secrets, vault, cert-manager, sealed-secrets, …) are
  Helm wrappers for secret-management tools; the directory holds no real secrets
  (those are SOPS-encrypted via `.sops.yaml`). Secret-protection patterns keyed on
  the literal token `secrets` — a `Read(…secrets/**)` deny glob, a Bash regex on
  `secrets\.`, a basename glob — false-positive on this taxonomy and can silently
  blind the read-only reviewers *and* the orchestrator (a `permissions.deny` Read
  rule is inherited by every read-only subagent). Narrow such a pattern to
  file-level (`.env`/`secrets.*`/`*.pem`/`*.key`), never a bare `secrets` path
  segment; never perpetuate a per-read `git show` workaround.
- **zsh expansion before `:`** — write `"${A}:${B}"`, not `$A:$B`; bare `$A:$B`
  trips zsh "bad substitution" (`:` is a parameter-expansion modifier).

### Context Architecture

- All shared operational conventions live in `AGENTS.md`.
- This file stays minimal — only Claude-Code-specific notes.
- Hard Constraints from [`talos-platform-base/AGENTS.md`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md) are captured in `AGENTS.md` § Hard Constraints and apply here as well.

### Documentation Entry Points

For the full architecture docs (ADRs, runbooks, C4): [`talos-platform-docs`](https://github.com/devobagmbh/talos-platform-docs).

Locally: `README.md` (top), `AGENTS.md` (conventions), `sub-layers/<name>/README.md` (sub-layer details).

Before every edit: read `AGENTS.md` + this file + the relevant sub-layer `README.md`.

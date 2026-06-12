# `talos-platform-apps` — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

Dieses Repo verfolgt den **mcp-server-Stil**: ein eigenes `.claude/`-Verzeichnis mit Subagents, Hooks und Settings. Anders als `talos-platform-base` (das auf das `kube-agent-harness`-Plugin wartet) liefern wir die Primitives in-tree, damit das Repo sofort autark ist.

### Hooks

- `.claude/hooks/require-review.sh` — PreToolUse-Gate für `Bash`-Commits. **Aktuell inaktiv** (nicht in `settings.json` gebunden). Hintergrund: bei 1 Maintainer wäre fail-closed Selbst-Sabotage (Bobby's Bus-Faktor-Kritik, 2026-05-26). Skript bleibt im Repo; Reaktivierung sobald M2 onboardet ist.
- `.claude/hooks/pre-commit` — klassischer Git-Pre-Commit-Pfad (rendered/-Detection, conventional-commit-Pattern). Ebenfalls dormant.

### Subagents — 5 Impl/Review-Rollen + 1 Build-Verifier + 2 Plan-Phase-Rollen

Tiered-Review-Modell, adaptiert aus `talos-mcp-server`. Auf **5 Impl/Review-Rollen reduziert (2026-05-26)** — bei 1 Maintainer ist ein 9-Rollen-*Review*-Apparat Theater. Hinzu kommt `catalog-evaluator` als separater Build-Zeit-Verifier: das ist *kein* sechstes Review-Theater, sondern die Judge-Builder-Trennung — ein Agent, der baut *und* sein eigenes Werk verifiziert, ist das dokumentierte Self-Verification-/Self-Preference-Failure (MAST FC3, arXiv:2410.21819 + 2402.08115). Reaktivierung der vollen Review-Hierarchie sobald M2 da ist. Die „5"-Zahl betrifft nur die **Impl/Review**-Achse (die 9→5-Reduktion); die Plan-Phase ist eine separate Achse und bringt das `catalog-planner`/`plan-reviewer`-Paar (unten) hinzu.

Verfügbar in `.claude/agents/`:

- `senior-implementer` — schreibt Code/Manifeste/Helm-Values; hat write+edit+bash
- `catalog-evaluator` — unabhängiger Build-Zeit-Acceptance-Verifier (deterministischer Gate + Semantik-ACs, Tamper-/Chart-Ref-Check); read+bash, kein write/edit; nie derselbe Kontext, der gebaut hat
- `staff-reviewer` — Primary Gate vor Commits, triagiert ggf. an Spezialisten
- `security-reviewer` — Vault/SOPS/cosign/SBOM/RBAC/Policies
- `operational-safety-reviewer` — Bootstrap-Ordnung, DR-Risiken, Backup-Pfade
- `researcher` — Recherche im base/anderen Repos, Findings-Synthese

Plan-Phase-Paar (Judge-Builder-Trennung, orchestriert vom `plan-catalog-app`-Skill):

- `catalog-planner` — schreibt den Catalog-App-Plan (Komponenten, Dependency-Graph + build_order, Capability-Mapping, Freeze-Line-Skizze, testbare ACs); Write-Scope nur `.work/plan/`, kein Verdict (Builder-Klasse)
- `plan-reviewer` — read-only Plan-Reviewer, kanonisches Verdict-Enum; eine Definition bedient konformations- und adversariale Persona (Stance per Brief)

Aus dem Git-Verlauf bei M2-Onboarding zurückzuholen: `senior-plan-reviewer`, `principal-architect-reviewer`, `provenance-reviewer`, `compatibility-reviewer`.

### Skills + Workflows

In-tree Claude-Code-Primitives für den Catalog-Build (Issues #17–#61), nach aktuellen Claude-Code- + LLM-Best-Practices (deterministischer Gate zuerst, LLM-Judge nur für die Semantik; Builder ≠ Verifier; parallele Personas statt sequenzieller Debatte):

- **`/ship-catalog-app <app>`** (`.claude/skills/ship-catalog-app/`) — **End-to-End-Orchestrator** für den vollen plan→approve→build-Bogen EINER Catalog-App in einer Session. Reine Orchestrierungsschicht: ruft die zwei Skills unten auf, dupliziert ihre Logik/Conventions NICHT. Drei Invarianten: (1) verpflichtender menschlicher **Plan-Freigabe-Gate** zwischen Plan und N PRs (headless → stop-after-plan); (2) **Merge-Gate mechanisch vorklassifiziert, Build-Skill als Backstop** — eine Komponente mit nicht-nach-`main`-gemergten `external_dependencies` ist `awaiting-merge` und wird nicht attemptet; ship's konservativer Pre-Check ist nur eine Dispatch-Spar-Optimierung vor diesem Backstop — einzige Garantie ist **kein falscher Build** (der autoritative Build-Check stoppt jede unzulässige Komponente); beide Fehlklassifikationen sind unschädlich (Über-Zulassung → verschwendeter Dispatch; false-stall, wenn eine Dependency extern nach dem Fetch gemergt wird → transient, vom Re-run gelöst); (3) **re-run-resumierbar** aus dem beobachteten Git-Status, kein Ship-State-File. Spec/DRY-Quelle: die SKILL.md + die zwei Sub-Skills (kein eigenes CONVENTIONS.md).
- **`/plan-catalog-app <app>`** (`.claude/skills/plan-catalog-app/`) — plant EINE Catalog-App (1-N Komponenten) durch einen konvergierenden plan→review→revise-Loop: `catalog-planner` schreibt den Plan, `plan-reviewer` reviewt ihn parallel als zwei Personas (konformations + adversarial, cross-model wo möglich), Finding-Ledger, harter Round-Cap 3, explizite Termination (konvergiert oder surfacet Residuals, schleift nie). Output: ein finding-freier Plan unter `.work/plan/<app>/`, den `/build-catalog-component` pro Komponente konsumiert. Planner ≠ Reviewer (Judge-Builder-Trennung). Spec/DRY-Quelle: `CONVENTIONS.md` im Skill-Verzeichnis.
- **`/build-catalog-component <sub-layer>/<component>`** (`.claude/skills/build-catalog-component/`) — baut EINE Komponente durch builder→verifier→reviewer in getrennten Kontexten; Fix-Loop-Cap 2; Branch + PR, nie Auto-Merge. **Pro-Session-Einheit für parallele unabhängige Sessions**: Phase 1 ruft `task worktree:create -- <sub-layer>/<component>` und arbeitet in einem eigenen git-Worktree (`.claude/worktrees/<slug>`) — mehrere Sessions laufen so parallel auf EINEM Clone (cross-session-sicherer `mkdir`-Lock; Branch-Name = Claim, zweite Session auf dieselbe Komponente schlägt fest fehl). Spec/DRY-Quelle: `CONVENTIONS.md` im Skill-Verzeichnis.
- **`catalog-fleet`** (`.claude/workflows/catalog-fleet.js`) — **optionaler Single-Operator-Fan-out**: EINE Session fächert N Komponenten auf (build→verify→review als Pipeline, Worktree pro Build via `task worktree:create`, schema-validierter Output, konsolidierter Report). **Primärpfad für Parallelität sind unabhängige Sessions + das Skill (oben)** — der Workflow ist nur für den Ein-Operator-Massen-Fan-out. Shared-File-Integration (capability-index, Sub-Layer-Aggregate) + PR bleiben serialisiert/menschlich. Erfordert expliziten Opt-in (Workflow-Tool).

### Rules (repo-local, path-scoped)

`.claude/rules/*.md` tragen die **Editor-Disziplin der Main-Session** für
Primitive-Edits — repo-lokal und self-contained, geladen via `paths:`-Frontmatter,
wenn du eine passende Datei liest/editierst (dokumentierter Claude-Code-Mechanismus,
`memory.md` § „Organize rules with `.claude/rules/`"). Sie ersetzen jede Abhängigkeit
von einer globalen User-Config:

- `agent-conventions.md` (`paths: .claude/agents/**`) — A1 (keine Peer-Namen im
  Body), A3 (Description = Routing-Surface), Verdict-Schema-Parität,
  Injection-Hardening-inline, judge≠builder, Evidence-Disziplin.
- `review-convergence.md` (`paths: .claude/{skills,agents,hooks,workflows}/**`) —
  konvergierender Review-Loop (parallele cross-model Personas statt sequenzieller
  Runden, Finding-Ledger, harter Round-Cap, explizite Termination), Escalation-on-
  critical, Harness-Evolution-2-Runden-Minimum.
- `self-containment.md` (`paths: .claude/**`) — kein Bezug auf eine persönliche
  globale Claude-Config; Subagent-Disziplin lebt **inline** im Agent-Body (Subagents
  laden diese Rules nicht); `task check:primitives` ist der deterministische Gate.

**Wichtig:** Subagents laden diese Rules NICHT (isolierter Kontext) — runtime-bindende
Disziplin steht inline im jeweiligen Agent-Body, die Rules erinnern nur den Editor.

### Settings

`.claude/settings.json` enthält:

- **Permissions-Allowlist** — reduziert Permission-Prompts (Bash, Read, Edit, Write, Glob, Grep, Agent + ausgewählte `mcp__github__*`-Tools).
- **Keine Hook-Bindungen aktiv** — siehe „Hooks"-Sektion oben.

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

- Alle geteilten operativen Konventionen leben in `AGENTS.md`.
- Diese Datei bleibt minimal — nur Claude-Code-spezifische Notes.
- Hard Constraints aus [`talos-platform-base/AGENTS.md`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md) sind in `AGENTS.md` § Hard Constraints aufgegriffen und gelten hier ebenfalls.

### Documentation Entry Points

Für die vollständige Architektur-Doku (ADRs, Runbooks, C4): [`talos-platform-docs`](https://github.com/devobagmbh/talos-platform-docs).

Lokal: `README.md` (Top), `AGENTS.md` (Konventionen), `sub-layers/<name>/README.md` (Sub-Layer-Details).

Vor jedem Edit: Lies `AGENTS.md` + diese Datei + ggf. den Sub-Layer-`README.md`.

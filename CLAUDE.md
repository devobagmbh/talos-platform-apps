# `talos-platform-apps` — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

Dieses Repo verfolgt den **mcp-server-Stil**: ein eigenes `.claude/`-Verzeichnis mit Subagents, Hooks und Settings. Anders als `talos-platform-base` (das auf das `kube-agent-harness`-Plugin wartet) liefern wir die Primitives in-tree, damit das Repo sofort autark ist.

### Hooks

- `.claude/hooks/require-review.sh` — PreToolUse-Gate für `Bash`-Commits. **Aktuell inaktiv** (nicht in `settings.json` gebunden). Hintergrund: bei 1 Maintainer wäre fail-closed Selbst-Sabotage (Bobby's Bus-Faktor-Kritik, 2026-05-26). Skript bleibt im Repo; Reaktivierung sobald M2 onboardet ist.
- `.claude/hooks/pre-commit` — klassischer Git-Pre-Commit-Pfad (rendered/-Detection, conventional-commit-Pattern). Ebenfalls dormant.

### Subagents — 5 Impl/Review-Rollen + 1 Build-Verifier

Tiered-Review-Modell, adaptiert aus `talos-mcp-server`. Auf **5 Impl/Review-Rollen reduziert (2026-05-26)** — bei 1 Maintainer ist ein 9-Rollen-*Review*-Apparat Theater. Hinzu kommt `catalog-evaluator` als separater Build-Zeit-Verifier: das ist *kein* sechstes Review-Theater, sondern die Judge-Builder-Trennung — ein Agent, der baut *und* sein eigenes Werk verifiziert, ist das dokumentierte Self-Verification-/Self-Preference-Failure (MAST FC3, arXiv:2410.21819 + 2402.08115). Reaktivierung der vollen Review-Hierarchie sobald M2 da ist.

Verfügbar in `.claude/agents/`:

- `senior-implementer` — schreibt Code/Manifeste/Helm-Values; hat write+edit+bash
- `catalog-evaluator` — unabhängiger Build-Zeit-Acceptance-Verifier (deterministischer Gate + Semantik-ACs, Tamper-/Chart-Ref-Check); read+bash, kein write/edit; nie derselbe Kontext, der gebaut hat
- `staff-reviewer` — Primary Gate vor Commits, triagiert ggf. an Spezialisten
- `security-reviewer` — Vault/SOPS/cosign/SBOM/RBAC/Policies
- `operational-safety-reviewer` — Bootstrap-Ordnung, DR-Risiken, Backup-Pfade
- `researcher` — Recherche im base/anderen Repos, Findings-Synthese

Aus dem Git-Verlauf bei M2-Onboarding zurückzuholen: `senior-plan-reviewer`, `principal-architect-reviewer`, `provenance-reviewer`, `compatibility-reviewer`.

### Skills + Workflows

In-tree Claude-Code-Primitives für den Catalog-Build (Issues #17–#61), nach aktuellen Claude-Code- + LLM-Best-Practices (deterministischer Gate zuerst, LLM-Judge nur für die Semantik; Builder ≠ Verifier; parallele Personas statt sequenzieller Debatte):

- **`/build-catalog-component <sub-layer>/<component>`** (`.claude/skills/build-catalog-component/`) — baut EINE Komponente durch builder→verifier→reviewer in getrennten Kontexten; Fix-Loop-Cap 2; Branch + PR, nie Auto-Merge. **Pro-Session-Einheit für parallele unabhängige Sessions**: Phase 1 ruft `task worktree:create -- <sub-layer>/<component>` und arbeitet in einem eigenen git-Worktree (`.claude/worktrees/<slug>`) — mehrere Sessions laufen so parallel auf EINEM Clone (cross-session-sicherer `mkdir`-Lock; Branch-Name = Claim, zweite Session auf dieselbe Komponente schlägt fest fehl). Spec/DRY-Quelle: `CONVENTIONS.md` im Skill-Verzeichnis.
- **`catalog-fleet`** (`.claude/workflows/catalog-fleet.js`) — **optionaler Single-Operator-Fan-out**: EINE Session fächert N Komponenten auf (build→verify→review als Pipeline, Worktree pro Build via `task worktree:create`, schema-validierter Output, konsolidierter Report). **Primärpfad für Parallelität sind unabhängige Sessions + das Skill (oben)** — der Workflow ist nur für den Ein-Operator-Massen-Fan-out. Shared-File-Integration (capability-index, Sub-Layer-Aggregate) + PR bleiben serialisiert/menschlich. Erfordert expliziten Opt-in (Workflow-Tool).

### Settings

`.claude/settings.json` enthält:

- **Permissions-Allowlist** — reduziert Permission-Prompts (Bash, Read, Edit, Write, Glob, Grep, Agent + ausgewählte `mcp__github__*`-Tools).
- **Keine Hook-Bindungen aktiv** — siehe „Hooks"-Sektion oben.

### Context Architecture

- Alle geteilten operativen Konventionen leben in `AGENTS.md`.
- Diese Datei bleibt minimal — nur Claude-Code-spezifische Notes.
- Hard Constraints aus [`talos-platform-base/AGENTS.md`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md) sind in `AGENTS.md` § Hard Constraints aufgegriffen und gelten hier ebenfalls.

### Documentation Entry Points

Für die vollständige Architektur-Doku (ADRs, Runbooks, C4): [`talos-platform-docs`](https://github.com/devobagmbh/talos-platform-docs).

Lokal: `README.md` (Top), `AGENTS.md` (Konventionen), `sub-layers/<name>/README.md` (Sub-Layer-Details).

Vor jedem Edit: Lies `AGENTS.md` + diese Datei + ggf. den Sub-Layer-`README.md`.

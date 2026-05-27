# `talos-platform-apps` — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

Dieses Repo verfolgt den **mcp-server-Stil**: ein eigenes `.claude/`-Verzeichnis mit Subagents, Hooks und Settings. Anders als `talos-platform-base` (das auf das `kube-agent-harness`-Plugin wartet) liefern wir die Primitives in-tree, damit das Repo sofort autark ist.

### Hooks

- `.claude/hooks/require-review.sh` — PreToolUse-Gate für `Bash`-Commits. **Aktuell inaktiv** (nicht in `settings.json` gebunden). Hintergrund: bei 1 Maintainer wäre fail-closed Selbst-Sabotage (Bobby's Bus-Faktor-Kritik, 2026-05-26). Skript bleibt im Repo; Reaktivierung sobald M2 onboardet ist.
- `.claude/hooks/pre-commit` — klassischer Git-Pre-Commit-Pfad (rendered/-Detection, conventional-commit-Pattern). Ebenfalls dormant.

### Subagents — reduziert auf 5 Rollen

Tiered-Review-Modell, adaptiert aus `talos-mcp-server`. Auf **5 Rollen reduziert (2026-05-26)** — bei 1 Maintainer ist ein 9-Rollen-Apparat Theater. Reaktivierung der vollen Hierarchie sobald M2 da ist.

Verfügbar in `.claude/agents/`:

- `senior-implementer` — schreibt Code/Manifeste/Helm-Values; hat write+edit+bash
- `staff-reviewer` — Primary Gate vor Commits, triagiert ggf. an Spezialisten
- `security-reviewer` — Vault/SOPS/cosign/SBOM/RBAC/Policies
- `operational-safety-reviewer` — Bootstrap-Ordnung, DR-Risiken, Backup-Pfade
- `researcher` — Recherche im base/anderen Repos, Findings-Synthese

Aus dem Git-Verlauf bei M2-Onboarding zurückzuholen: `senior-plan-reviewer`, `principal-architect-reviewer`, `provenance-reviewer`, `compatibility-reviewer`.

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

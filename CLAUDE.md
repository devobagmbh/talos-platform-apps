# `talos-platform-apps` — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

Dieses Repo verfolgt den **mcp-server-Stil**: ein eigenes `.claude/`-Verzeichnis mit Subagents, Hooks und Settings. Anders als `talos-platform-base` (das auf das `kube-agent-harness`-Plugin wartet) liefern wir die Primitives in-tree, damit das Repo sofort autark ist.

### Hooks

- `.claude/hooks/require-review.sh` — PreToolUse-Gate für `Bash`-Commits und `mcp__github__push_files`. Fail-closed: verhindert Commits ohne Review-Artefakte.
- `.claude/hooks/pre-commit` — klassischer Git-Pre-Commit-Pfad (rendered/-Detection, conventional-commit-Pattern).

### Subagents

Tiered-Review-Modell, adaptiert aus `talos-mcp-server`. Implementer und Reviewer sind immer verschiedene Agents — Self-Review ist verboten.

Verfügbar in `.claude/agents/`:

- `senior-implementer` — schreibt Code/Manifeste/Helm-Values; hat write+edit+bash
- `senior-plan-reviewer` — reviewt Plans vor Implementierung
- `staff-reviewer` — Primary Gate vor Commits
- `principal-architect-reviewer` — Architektur-Konsistenz, ADR-Alignment
- `security-reviewer` — Vault/SOPS/cosign/SBOM/RBAC-Themen
- `operational-safety-reviewer` — Bootstrap-Ordnung, DR-Risiken, Backup-Pfade
- `provenance-reviewer` — cosign-Identity, SLSA-Provenance, OCI-Push-Hygiene
- `compatibility-reviewer` — `compatibility.yaml`-Korrektheit, Konsumenten-Impact
- `researcher` — Recherche im base/anderen Repos, Findings-Synthese

### Settings

`.claude/settings.json` enthält:
- **Permissions-Allowlist** — reduziert Permission-Prompts (Bash, Read, Edit, Write, Glob, Grep, Agent + ausgewählte `mcp__github__*`-Tools).
- **Hook-Bindung** — PreToolUse-Hook für `Bash` und Push-Tools auf `require-review.sh`.

### Context Architecture

- Alle geteilten operativen Konventionen leben in `AGENTS.md`.
- Diese Datei bleibt minimal — nur Claude-Code-spezifische Notes.
- Hard Constraints aus [`talos-platform-base/AGENTS.md`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md) sind in `AGENTS.md` § Hard Constraints aufgegriffen und gelten hier ebenfalls.

### Documentation Entry Points

Für die vollständige Architektur-Doku (ADRs, Runbooks, C4): [`talos-platform-docs`](https://github.com/devobagmbh/talos-platform-docs).

Lokal: `README.md` (Top), `AGENTS.md` (Konventionen), `sub-layers/<name>/README.md` (Sub-Layer-Details).

Vor jedem Edit: Lies `AGENTS.md` + diese Datei + ggf. den Sub-Layer-`README.md`.

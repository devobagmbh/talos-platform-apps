# AGENTS.md — `talos-platform-apps`

Maschinenlesbare Konventionen für AI-Agenten und menschliche Maintainer.
**Lies diese Datei vor jeder Arbeit.** Source of Truth.

---

## Repository Purpose

`talos-platform-apps` bündelt **gemeinsam genutzte Plattform-Sub-Layer** der Devoba Talos-Plattform und publiziert sie als signierte OCI-Artefakte. Seeder- und DHQ-Cluster konsumieren diese Layer per Tag.

Acht Sub-Layer: `automation`, `databases`, `dns`, `lifecycle`, `monitoring`, `registry`, `secrets`, `storage-objects`.

**NICHT** in diesem Repo:
- Cluster-Identität (Node-IPs, Hostnamen, TLS-Cert-CNs)
- Echte Secrets (Vault-Tokens, age-Keys, Passwords)
- Cluster-spezifische Helm-Overrides (gehören in `talos-seeder-cluster` und `talos-dhq-cluster`)
- Runnable Cluster oder kubeconfigs

## Project Structure

```text
talos-platform-apps/
├── README.md                       — Top-Übersicht + Install-Anleitung
├── AGENTS.md                       — diese Datei (Source of Truth)
├── CLAUDE.md                       — Claude-Code-Entry-Point, importiert @AGENTS.md
├── devbox.json                     — Tool-Pinning (Nix)
├── devbox.lock                     — generiert von devbox
├── .envrc                          — direnv: aktiviert Devbox-Shell
├── .sops.yaml.tmpl                 — Recipient-Template; wird zu .sops.yaml nach Issue #3
├── .gitignore
├── Taskfile.yml                    — go-task Targets (Issue #11.1)
├── sub-layers/<name>/
│   ├── README.md                   — Komponenten, Konsumenten, ADR-Verweise
│   ├── helm/                       — Helm-Values (Defaults; cluster-spezifisches in Konsumenten-Repos)
│   ├── manifests/                  — Raw-Manifeste (CRs, NetPols, Bucket-Defs)
│   ├── rendered/                   — gitignored, Output von helm template
│   └── compatibility.yaml          — requires/provides (Issue #11.3)
├── .claude/                        — Tool-Konfig für Claude Code
│   ├── settings.json               — Permissions + Hook-Bindung
│   ├── agents/                     — Subagent-Definitionen
│   └── hooks/                      — PreToolUse/PostToolUse-Skripte
└── .github/
    ├── CODEOWNERS
    ├── dependabot.yml
    ├── PULL_REQUEST_TEMPLATE.md
    ├── ISSUE_TEMPLATE/
    └── workflows/                  — GHA-Pipelines (oci-publish, scorecard, …)
```

## Build, Test, Development Commands

Voraussetzung: Devbox + direnv. Nach `direnv allow` ist alle Tools im PATH.

| Befehl | Zweck |
|---|---|
| `task lint` | `helm lint` + `kubeconform` über alle rendered/-Outputs |
| `task render -- <sub-layer>` | `helm template` für einen Sub-Layer |
| `task render` | render aller Sub-Layer (Matrix) |
| `task push -- <sub-layer> <tag>` | `oras push ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>:<tag>` |
| `task sign -- <sub-layer> <tag>` | `cosign sign --yes` |
| `task attest -- <sub-layer> <tag>` | SBOM (syft → CycloneDX → cosign attest) + SLSA-Provenance |
| `task publish -- <sub-layer> <tag>` | render → push → sign → attest in einem Rutsch |
| `task ci` | **lokale Reproduktion der GHA-Pipeline** (alle Sub-Layer, Lint + Render, kein Push) |

**Niemals `make` verwenden** — die Konvention ist go-task.

## Coding Style & Naming

- **YAML**: 2-Space-Indent, keine Tabs, Block-Style bevorzugen
- **Sub-Layer-Verzeichnisname == Sub-Layer-Identität**: `sub-layers/monitoring/` produziert OCI-Tag `monitoring-v<X.Y.Z>`
- **README pro Sub-Layer**: Komponenten + Konsumenten + Backlog-Issue + ADR-Verweise (siehe bestehende READMEs als Vorlage)
- **Sprache**: Deutsch in `README.md`, `AGENTS.md` und Doku. Helm-Werte/Code folgen Upstream (englisch).
- **Sub-Layer-Versionierung**: SemVer pro Sub-Layer (`<sub-layer>-vMAJ.MIN.PATCH`). Unabhängiger Lifecycle pro Sub-Layer.

## Testing Guidelines

Dieses Repo hat keinen Live-Cluster. Validierung ist Render- und Policy-fokussiert:

- `task lint` muss vor jedem PR-Open grün sein
- `task render -- <sub-layer>` produziert valide YAML gegen den jeweiligen Default-Werten-Stack
- Schema-Konformität wird via `kubeconform` geprüft
- Cosign-/Provenance-Signing wird in der GHA-Pipeline keyless verifiziert (`cosign verify`)
- Echte Cluster-Verifikation gehört in die Konsumenten-Repos (`talos-seeder-cluster`, `talos-dhq-cluster`)

## Commits & Pull Requests

- **Conventional Commits** mit Sub-Layer-Scope: `feat(monitoring): …`, `fix(dns): …`, `chore(automation): …`, `docs: …`
- Ein Commit = eine logische Einheit. Render-Output (`rendered/`) niemals committen.
- **Breaking-Change-Bumps**: ein neues Major-Tag (`<sub-layer>-v2.0.0`) erfordert einen `BREAKING CHANGE:`-Footer im Commit und einen Eintrag im Top-`CHANGELOG.md` (wenn vorhanden).
- PR-Body: was geändert + warum + Validation-Steps (siehe `.github/PULL_REQUEST_TEMPLATE.md`).
- PRs brauchen **Subagent-Reviews** (siehe Multi-Agent-Coordination weiter unten); der `require-review.sh`-Hook verhindert Direkt-Commits ohne Review-Artefakte.

## CI-Konventionen (verbindlich)

Drei Regeln, projektweit:

1. **Devbox-Cache aktiv** — Jeder GHA-Job nutzt `jetify-com/devbox-install-action@v0.x` mit `enable-cache: true`. Tool-Versionen kommen aus `devbox.json`/`devbox.lock`. **Niemals `actions/setup-go`, `actions/setup-helm` etc.**
2. **Lokal reproduzierbar** — Jeder Task läuft auf der Workstation 1:1 wie in CI. Vor `git push` läuft `task ci` lokal. Kein GHA-spezifischer Code in Tasks (`$GITHUB_ACTIONS`-Checks o. Ä. verboten).
3. **Pipeline = Task-Caller** — Workflow-Steps rufen ausschließlich `task <name>`. Keine Inline-`helm template`/`oras push`/`cosign sign`-Kommandos im YAML. Verhalten ändert man im Task, nicht im Workflow.

## Hard Constraints (universal cluster invariants)

Nicht ohne explizite Maintainer-Freigabe relaxen.

- **Kein direktes `kubectl apply` gegen Cluster** aus diesem Repo. Dieses Repo publiziert OCI-Artefakte; Cluster-Apply läuft via Argo in den Konsumenten-Repos.
- **Keine echten Secrets im Repo** — auch nicht in Tests. `.sops.yaml.tmpl` bleibt Template bis Issue #3 die vier age-Recipients liefert.
- **Kein `make`-Target** — die Konvention ist go-task. Wer `Makefile` einreicht: Review wird ablehnen.
- **Kein Render-Output committen** — `rendered/` ist gitignored. Geprüft via `pre-commit`-Hook.
- **Kein `.envrc.local`** ins Repo — direnv-Lokal-Overrides bleiben lokal.
- **Kein `.claude/` mit personalisierten Settings committen** — `settings.local.json` ist gitignored.
- **OCI-Pfade hardcoded**: `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>:<tag>` — Renaming des Org-Pfads erfordert Coordination mit allen Konsumenten.
- **cosign keyless mit GHA-OIDC**: Signing-Identity ist die Workflow-Identity. Keine Long-Lived-Keys committen.

## Sub-Layer-Konventionen

- **Ein Verzeichnis pro Sub-Layer** unter `sub-layers/<name>/`. Verzeichnisname == OCI-Artefakt-Name.
- **Pro Sub-Layer**: `README.md` (Pflicht), `helm/` oder `manifests/` (Inhalt), `compatibility.yaml` (Pflicht ab Issue #11.3).
- **Konsumenten-Trennung**: dieses Repo enthält Defaults und shared-Values. Cluster-spezifisches (Replica-Counts, VIPs, OIDC-Issuer-URLs) gehört in die Konsumenten-Repos.
- **`compatibility.yaml`** deklariert die kompatible `talos-platform-base`-Version-Range:
  ```yaml
  requires:
    talos-platform-base: ">=v0.4.0 <v1.0.0"
  provides:
    - name: <sub-layer>
      apis:
        - <chart-name>@<chart-version>
  ```

## Multi-Agent-Coordination

`.claude/agents/` listet spezialisierte Subagenten. Workflow:

| Phase | Agent | Output |
|---|---|---|
| Planung | `senior-plan-reviewer` | Plan reviewt, Risiken markiert |
| Recherche (optional) | `researcher` | Findings + Quellen |
| Implementierung | `senior-implementer` | Code-Diff |
| Security-Review | `security-reviewer` | Findings |
| Operational-Safety | `operational-safety-reviewer` | Findings |
| Provenance-Review (bei Pipeline/Signing-Themen) | `provenance-reviewer` | Findings |
| Compatibility-Review (bei `compatibility.yaml`-Edits) | `compatibility-reviewer` | Findings |
| Architektur-Review | `principal-architect-reviewer` | Findings |
| **Gate** | `staff-reviewer` | Approve oder Block |

**Niemals Self-Review** — Implementierer und Reviewer sind immer verschiedene Agents. Der `require-review.sh`-Hook prüft Review-Artefakte vor jedem Push.

## Validation Checklist

Vor PR-Open:

- [ ] `task lint` grün
- [ ] `task render -- <touched-sub-layer>` grün
- [ ] `task ci` grün (volle Pipeline lokal)
- [ ] `compatibility.yaml` aktualisiert wenn Helm-Chart-Version geändert wurde
- [ ] README im betroffenen Sub-Layer aktualisiert wenn Komponenten oder Konsumenten sich geändert haben
- [ ] Konventionalcommits-Style mit Sub-Layer-Scope
- [ ] Mindestens ein Reviewer-Subagent ausgeführt; bei Pipeline-/Signing-Themen zusätzlich `provenance-reviewer`

## References

- [`README.md`](README.md) — Top-Übersicht + Install
- [`talos-platform-docs/adr/0009-platform-layer-model.md`](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) — Multi-Layer-OCI-Distribution
- [`talos-platform-docs/operations/day-zero-backlog.md`](https://github.com/devobagmbh/talos-platform-docs/blob/main/operations/day-zero-backlog.md) — Phase-Plan
- [`talos-platform-base/AGENTS.md`](https://github.com/Nosmoht/talos-platform-base/blob/main/AGENTS.md) — Upstream-Base-Konventionen (PNI-Capability-Contract, Hard Constraints, die hier ererbt sind)

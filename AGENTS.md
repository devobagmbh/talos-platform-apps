# AGENTS.md — `talos-platform-apps`

Maschinenlesbare Konventionen für AI-Agenten und menschliche Maintainer.
**Lies diese Datei vor jeder Arbeit.** Source of Truth.

---

## Repository Purpose

`talos-platform-apps` ist der **zentrale Plattform-Katalog** der Devoba Talos-Plattform. **Alles, was nicht Substrat ist** (nicht in `talos-platform-base`), lebt hier und wird als signierte OCI-Artefakte publiziert. Consumer-Cluster-Repos (Seeder, Office-Lab) **bedienen sich aus dem Katalog** — sie referenzieren per Tag genau die Komponenten, die sie brauchen. Arbeitsteilung: **Base = Substrat (Talos + Cilium + ArgoCD + cert-approver), Apps = Katalog (alles Übrige), Consumer = Komposition.**

**Granularität**: Die OCI-Distribution-Unit ist die **Komponente**, der Sub-Layer ist eine organisatorische Klammer (Verzeichnis-Gruppierung). Siehe ADR-0009 § OCI-Granularität. Sub-Layer als Klammer (Stand 2026-06-03, Taxonomie-Entscheid #16): `automation`, `databases`, `lifecycle`, `observability` (vormals `monitoring`), `registry`, `secrets`, `storage-objects` plus die capability-getriebenen `identity`, `network`, `compute`, `storage-block`, `security` — innerhalb jedes Sub-Layers leben 1-N Komponenten als eigenständig versionierte OCI-Artefakte. `kube-prometheus-stack` ist ein *Stack* (Komposition aus Einzel-Apps), keine eigene Komponente.

**NICHT** in diesem Repo:

- Cluster-Identität (Node-IPs, Hostnamen, TLS-Cert-CNs)
- Echte Secrets (Vault-Tokens, age-Keys, Passwords)
- Cluster-spezifische Helm-Overrides (gehören in `talos-seeder-cluster` und `talos-office-lab-cluster`)
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
├── sub-layers/<sub-layer>/
│   ├── README.md                   — Sub-Layer-Übersicht, Komponenten-Liste, ADR-Verweise
│   ├── compatibility.yaml          — Sub-Layer-Aggregate (listet Komponenten)
│   └── components/<component>/
│       ├── README.md               — Komponenten-Beschreibung, sync-wave-Position, OCI-Pfad
│       ├── compatibility.yaml      — requires/provides der Komponente
│       ├── helm/*.yaml             — Helm-Chart-Referenz (chart/repo/version + values) ODER metadata.inline für Stubs
│       ├── manifests/*.yaml        — Raw-Manifeste (CRs, NetPols, Bucket-Defs)
│       └── rendered/               — gitignored, Output von helm template + manifest-Konkatenation
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
| `task lint` | YAML/Markdown-Lint über `sub-layers/`, `.github/`, `Taskfile.yml` |
| `task lint:rendered` | `kubeconform` über alle Komponenten-`rendered/`-Outputs |
| `task render:one -- <sub-layer>/<component>` | `helm template` für eine Komponente |
| `task render:sublayer -- <sub-layer>` | rendert alle Komponenten eines Sub-Layers |
| `task render` | render aller Komponenten aller Sub-Layer (Matrix) |
| `task push -- <sub-layer>/<component> <tag>` | `helm push` nach `oci://.../<sub-layer>/<component>:<tag>` |
| `task sign -- <sub-layer>/<component> <tag>` | `cosign sign --yes` (lokale Registries → skip) |
| `task attest -- <sub-layer>/<component> <tag>` | SBOM (syft → CycloneDX → cosign attest) + SLSA-Provenance — Phase 2+ |
| `task publish -- <sub-layer>/<component> <tag>` | render → package → push → sign in einem Rutsch |
| `task publish:sublayer -- <sub-layer> <tag>` | publish aller Komponenten eines Sub-Layers mit gleichem Tag |
| `task ci` | **lokale Reproduktion der GHA-Pipeline** (alle Komponenten, Lint + Render + Conftest, kein Push) |

**Niemals `make` verwenden** — die Konvention ist go-task.

**Taskfile-Konventionen**:

- `silent: true` global — Commands echoen sich nicht selbst
- **Logik wohnt im Taskfile**, nicht in externen `scripts/`-Bash-Files. Auch komplexer Bash-Code wird inline in `cmds:` umgesetzt (Multi-Line `|`). Externe Scripts würden die „Pipeline = Task-Caller"-Konvention untergraben (Pipeline → Task → Script wäre eine Stufe zu tief).

## Coding Style & Naming

- **YAML**: 2-Space-Indent, keine Tabs, Block-Style bevorzugen
- **Verzeichnisname == Identität**: `sub-layers/lifecycle/components/crossplane/` produziert OCI-Pfad `<registry>/lifecycle/crossplane` mit Git-Tag-Pattern `lifecycle/crossplane-vX.Y.Z`
- **README pro Sub-Layer UND pro Komponente**: Sub-Layer-README listet die Komponenten + sync-wave-Reihenfolge; Komponenten-README beschreibt Inhalt + OCI-Pfad + sync-wave + ADR-Verweise.
- **Sprache**: Deutsch in `README.md`, `AGENTS.md` und Doku. Helm-Werte/Code folgen Upstream (englisch).
- **Versionierung pro Komponente**: SemVer (`<sub-layer>/<component>-vMAJ.MIN.PATCH`). Jede Komponente hat einen unabhängigen Lifecycle.

## Testing Guidelines

Dieses Repo hat keinen Live-Cluster. Validierung ist Render- und Policy-fokussiert:

- `task lint` muss vor jedem PR-Open grün sein
- `task render -- <sub-layer>` produziert valide YAML gegen den jeweiligen Default-Werten-Stack
- Schema-Konformität wird via `kubeconform` geprüft
- Cosign-/Provenance-Signing wird in der GHA-Pipeline keyless verifiziert (`cosign verify`)
- Echte Cluster-Verifikation gehört in die Konsumenten-Repos (`talos-seeder-cluster`, `talos-office-lab-cluster`)

## Commits & Pull Requests

- **Conventional Commits** mit Sub-Layer- oder Komponenten-Scope: `feat(lifecycle): …`, `feat(lifecycle/crossplane): …`, `fix(secrets): …`, `chore(automation): …`, `docs: …`
- Ein Commit = eine logische Einheit. Render-Output (`rendered/`) niemals committen.
- **Breaking-Change-Bumps**: ein neues Major-Tag (`<sub-layer>/<component>-v2.0.0`) erfordert einen `BREAKING CHANGE:`-Footer im Commit und einen Eintrag im Top-`CHANGELOG.md` (wenn vorhanden).
- PR-Body: was geändert + warum + Validation-Steps (siehe `.github/PULL_REQUEST_TEMPLATE.md`).
- PRs sollen **Subagent-Reviews** durchlaufen (siehe Multi-Agent-Coordination weiter unten). Der `require-review.sh`-Hook ist **bewusst inaktiv** (nicht in `settings.json` gebunden) bis M2 onboardet ist — bei 1 Maintainer wäre fail-closed Selbst-Sabotage. Hook-Skripte bleiben im Repo und werden reaktiviert sobald Multi-Maintainer-Workflow real wird.

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
- **OCI-Pfade hardcoded**: `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>/<component>:<tag>` — Renaming des Org-Pfads erfordert Coordination mit allen Konsumenten.
- **cosign keyless mit GHA-OIDC**: Signing-Identity ist die Workflow-Identity. Keine Long-Lived-Keys committen.

## Sub-Layer- und Komponenten-Konventionen

- **Ein Verzeichnis pro Sub-Layer** unter `sub-layers/<name>/`, mit `components/<component>/` darunter pro OCI-Artefakt. Verzeichnisname == OCI-Pfad-Komponente.
- **Pro Sub-Layer**: `README.md` (Pflicht, listet Komponenten + sync-wave-Reihenfolge), `compatibility.yaml` (Aggregate).
- **Pro Komponente**: `README.md` (Pflicht: Inhalt + OCI-Pfad + sync-wave + ADR-Verweise), `compatibility.yaml` (Pflicht: requires/provides), `helm/` oder `manifests/` (Inhalt).
- **Konsumenten-Trennung**: dieses Repo enthält Defaults und shared-Values. Cluster-spezifisches (Replica-Counts, VIPs, OIDC-Issuer-URLs) gehört in die Konsumenten-Repos.
- **Argo-Application-Definitionen leben im Konsumenten-Cluster-Repo**, nicht hier. Pro Komponente eine `Application`-CR mit `argocd.argoproj.io/sync-wave`-Annotation. Für lokale End-to-End-Tests gibt es `local/argo-apps/<sub-layer>/<component>.yaml`-Templates im apps-Repo.
- **`compatibility.yaml` pro Komponente** deklariert die Komponenten-Abhängigkeiten:

  ```yaml
  requires:
    talos-platform-base: ">=v0.4.0 <v1.0.0"
    lifecycle/crossplane: ">=v0.1.0"   # andere Komponente desselben Repos
  provides:
    - name: <component>
      apis:
        - <chart-name>@<chart-version>
  ```

- **Sub-Layer-`compatibility.yaml`** ist ein Aggregate, das die Komponenten listet:

  ```yaml
  components:
    - crossplane    # sync-wave 0
    - ipxe          # sync-wave 0
    - providers     # sync-wave 10
    - compositions  # sync-wave 20
  ```

## Multi-Agent-Coordination

`.claude/agents/` listet spezialisierte Subagenten. Reduziert auf **5 Rollen** (2026-05-26, Bobby's Bus-Faktor-Kritik) — bei 1 Maintainer ist eine differenzierte 9-Rollen-Hierarchie Self-Review-Theater. Bei M2-Onboarding kommen `senior-plan-reviewer`, `principal-architect-reviewer`, `provenance-reviewer` und `compatibility-reviewer` aus dem Git-Verlauf zurück.

| Phase | Agent | Output |
|---|---|---|
| Recherche (optional) | `researcher` | Findings + Quellen |
| Implementierung | `senior-implementer` | Code-Diff |
| Security-Review (Vault/SOPS/cosign/RBAC/Policies) | `security-reviewer` | Findings |
| Operational-Safety (Bootstrap/DR/Backup) | `operational-safety-reviewer` | Findings |
| **Gate** (Triage + Approve oder Block) | `staff-reviewer` | Approve oder Block |

**Self-Review ist auch bei 1 Maintainer unerwünscht, aber nicht hart blockiert** — Wechsel des Agent-Hut ist ein Anti-Drift-Mechanismus, kein Vier-Augen-Prinzip-Ersatz. Sobald M2 da ist, wird der `require-review.sh`-Hook reaktiviert und das volle 9-Agent-Modell zurückgeholt.

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

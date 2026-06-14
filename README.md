# talos-platform-apps

[![Talos Linux](https://img.shields.io/badge/Talos%20Linux-1.13.0-ff7300?style=flat-square)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36.0-326ce5?style=flat-square&logo=kubernetes)](https://kubernetes.io/)
[![Cilium](https://img.shields.io/badge/Cilium-1.19.3-F8C517?style=flat-square&logo=cilium)](https://cilium.io/)
[![Gateway API](https://img.shields.io/badge/Gateway%20API-v1.2-326CE5?style=flat-square&logo=kubernetes)](https://gateway-api.sigs.k8s.io/)
[![Helm](https://img.shields.io/badge/Helm-v3-0F1689?style=flat-square&logo=helm)](https://helm.sh/)
[![cosign](https://img.shields.io/badge/cosign-2.4%2B-2E7D9A?style=flat-square&logo=sigstore)](https://github.com/sigstore/cosign)
[![ORAS](https://img.shields.io/badge/ORAS-1.2%2B-1E3F66?style=flat-square)](https://oras.land/)
[![Conftest](https://img.shields.io/badge/Conftest-OPA%20Rego-7D4698?style=flat-square&logo=openpolicyagent)](https://www.conftest.dev/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-7.7-EF7B4D?style=flat-square&logo=argo)](https://argo-cd.readthedocs.io/)
[![cert-manager](https://img.shields.io/badge/cert--manager-1.17-0A6E32?style=flat-square)](https://cert-manager.io/)
[![kind](https://img.shields.io/badge/kind-local%20K8s-326CE5?style=flat-square&logo=kubernetes)](https://kind.sigs.k8s.io/)
[![mkcert](https://img.shields.io/badge/mkcert-Local%20TLS-1F305F?style=flat-square)](https://github.com/FiloSottile/mkcert)
[![Devbox](https://img.shields.io/badge/Devbox-Nix--based-31135a?style=flat-square)](https://www.jetify.com/devbox/)
[![direnv](https://img.shields.io/badge/direnv-2.36%2B-FFD400?style=flat-square)](https://direnv.net/)
[![Taskfile](https://img.shields.io/badge/Taskfile-v3-29BEB0?style=flat-square&logo=Task)](https://taskfile.dev/)
[![GitHub Actions](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/features/actions)

OCI-Sub-Layer der Devoba Talos-Plattform: `lifecycle`, `storage-objects`, `registry`, `databases`, `secrets`, `automation` und `observability`. Vorgerenderte Manifeste mit cosign-Signatur, SLSA-v1-Provenance und CycloneDX-SBOM. Von Consumer-Cluster-Repos konsumiert.

## Zweck

Dieses Repo ist der **zentrale Plattform-Katalog** der Devoba Talos-Plattform: **alles, was nicht Substrat ist** (nicht in `talos-platform-base` gehört), lebt hier als eigenständig versionierte, signierte OCI-Artefakte — Helm-Charts + Werte + ggf. Custom-Manifeste, in CI zu fertigen Manifesten vorgerendert. **Consumer-Cluster-Repos bedienen sich aus dem Katalog**, indem sie genau die OCI-Komponenten referenzieren, die sie brauchen (per Tag / Argo `targetRevision`, nicht per Helm-Render zur Apply-Zeit). Arbeitsteilung: **Base = Substrat, Apps = Katalog, Consumer = Komposition** — was nicht Substrat ist, gehört in den Katalog, nie in die Base.

Begründung: deterministische, reviewbare Deployment-Artefakte mit kryptografischer Supply-Chain-Verifikation. Cluster-Update = Tag-Bump in der Konsumenten-Konfiguration. Siehe [ADR-0009](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md).

## Sub-Layer- und Komponenten-Übersicht

OCI-Distribution erfolgt **pro Komponente** (ADR-0009 Revision 2026-05-26). Sub-Layer bleibt als Verzeichnis-Klammer und Tag-Namespace.

| Sub-Layer | Komponenten | Backlog-Issue |
|---|---|---|
| [`automation`](sub-layers/automation/) | renovate, velero | #16 |
| [`databases`](sub-layers/databases/) | cnpg | #15 |
| [`lifecycle`](sub-layers/lifecycle/) | crossplane, ipxe, providers, compositions | #12 |
| [`observability`](sub-layers/observability/) | kube-prometheus-stack, loki, mimir, tempo, alloy, grafana | #17 |
| [`registry`](sub-layers/registry/) | harbor | #14 |
| [`secrets`](sub-layers/secrets/) | external-secrets, clustersecretstore-defaults | #15a |
| [`storage-objects`](sub-layers/storage-objects/) | garage, garage-buckets | #13 |

Pro Sub-Layer existiert ein `README.md` mit Komponenten-Tabelle inkl. sync-wave-Reihenfolge. Pro Komponente ein eigenes `README.md` + `compatibility.yaml` mit `requires`-Block (Komponenten-Dependencies inkl. Cross-Sub-Layer wie `databases/cnpg` für Harbor).

## Local Setup

Die Dev-Umgebung läuft komplett über **Devbox** (Nix-basiert) + **direnv**. Damit ist die Tool-Version pro Repo gepinnt und nach `cd` automatisch im PATH — kein globales `brew install` nötig.

### Voraussetzungen

| Tool | Version | Installations-Hinweis |
|---|---|---|
| **Devbox** | ≥ 0.16 | `curl -fsSL https://get.jetify.com/devbox \| bash` |
| **direnv** | ≥ 2.36 | macOS: `brew install direnv`; Linux: Distro-Paket. Hook in deine Shell (siehe [direnv.net/docs/hook.html](https://direnv.net/docs/hook.html)) |
| **git** | ≥ 2.40 | bereits installiert |

### Einrichten

```bash
git clone git@github.com:devobagmbh/talos-platform-apps.git
cd talos-platform-apps
direnv allow
```

`direnv allow` löst das `.envrc` aus, das Devbox aktiviert. Beim ersten Aufruf installiert Devbox alle Tools (`helm`, `kubectl`, `cosign`, `oras`, `syft`, `go-task`, `yq`, `jq`, `sops`, `age`) in einen reproduzierbaren Nix-Store. Folge-`cd`s in das Repo schalten die Umgebung automatisch um.

### Tools, die Devbox bereitstellt

Siehe `devbox.json`. Versionen werden bei Bedarf in `devbox.lock` gepinnt — Updates erfolgen kontrolliert per `devbox update`.

### Tasks (statt make)

`go-task` ersetzt make. Aufgaben werden in `Taskfile.yml` deklariert (kommt in einer Folge-Iteration). Beispielhafte Targets:

```bash
task render -- observability         # rendert sub-layers/observability zu rendered/manifest.yaml
task sign   -- observability v0.1.0  # cosign sign des publizierten OCI-Tags
task attest -- observability v0.1.0  # SBOM + SLSA-Provenance als Attestations
task publish -- observability v0.1.0 # render → push → sign → attest in einem Rutsch
task ci                           # lokale Reproduktion der GHA-Pipeline
```

### Lokales Live-Testing (Talos + ArgoCD)

Für End-to-End-Tests einzelner Sub-Layer (Render → OCI-Push → Argo-Sync → Apply) gibt es einen prod-konformen **Talos**-Cluster (docker provisioner) — gleiches Substrat wie die Consumer-Cluster (Talos-Nodes, Cilium-CNI, Gateway-API, kube-proxy aus, KubePrism) — mit einer lokalen OCI-Registry hinter `registry.localhost.direct` (mkcert-TLS):

```bash
task local:up                                  # Talos + Cilium + Gateway + ArgoCD + Registry-Bridge
task local:publish -- lifecycle/crossplane 0.0.0-dev  # Komponente in die lokale Registry pushen
task local:apply   -- lifecycle 0.0.0-dev      # Argo-Applications des Sub-Layers anlegen
task local:argo:ui                             # https://argocd.localhost.direct öffnen
task local:down                                # alles abreißen
```

Vollständige Architektur, Endpoints, Komponentendetails und Troubleshooting: [`local/README.md`](local/README.md).

### CI

Die produktive Pipeline läuft auf **GitHub Actions** (Workflows unter `.github/workflows/`). Trigger: PRs (Render + Lint, kein Push) und Tag-Push `<sub-layer>-vX.Y.Z` (Render + OCI-Push + cosign-Sign + SBOM-/Provenance-Attest). cosign-Signing erfolgt keyless über die GHA-OIDC-Identity.

**Drei verbindliche CI-Regeln** für dieses und alle weiteren Plattform-Repos:

1. **Devbox-Cache aktiv**: Jeder Job nutzt `jetify-com/devbox-install-action` mit `enable-cache: true`. Tool-Versionen kommen ausschließlich aus `devbox.json`/`devbox.lock` — keine separaten `actions/setup-go`/`-helm`/`-kubectl`-Steps. Damit ist die CI-Umgebung byte-identisch zur Workstation und Builds sind nach dem ersten Lauf cache-warm.
2. **Lokal reproduzierbar**: Jeder einzelne Task im `Taskfile.yml` läuft auf der Workstation 1:1 wie in CI. Vor `git push` wird die volle Pipeline lokal durchgespielt (`task ci`). Kein GHA-spezifischer Code in Tasks — Außenlogik (OIDC, Tag-Erkennung, Matrix) bleibt im Workflow.
3. **Pipeline = dünner Task-Caller**: Workflow-Steps rufen ausschließlich `task <name>` auf. Keine Inline-`helm template`/`oras push`/`cosign sign`-Kommandos im YAML. Wer Pipeline-Verhalten ändern will, ändert den Task — Workflow-Diffs bleiben minimal und review-arm.

## Render-/Sign-/Publish-Workflow

```
Helm-Chart + Values
        │
        ▼
 helm template
        │
        ▼
 rendered/manifest.yaml
        │
        ▼
oras push ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>:<tag>
        │
        ▼
 cosign sign --yes
        │
        ▼
 syft → CycloneDX-SBOM → cosign attest
        │
        ▼
 slsa-github-generator → Provenance → cosign attest
```

Pipeline-Implementierung folgt in einer separaten Iteration (Task aus Phase 2 des [day-zero-backlog](https://github.com/devobagmbh/talos-platform-docs/blob/main/operations/day-zero-backlog.md)).

## Konventionen

- **Sub-Layer-Versionierung**: SemVer pro Sub-Layer (`<sub-layer>-vMAJ.MIN.PATCH`). Jeder Sub-Layer hat einen unabhängigen Lifecycle.
- **OCI-Pfade**: `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>:<tag>` als Manifest, gleicher Pfad für SBOM/Provenance-Attestations.
- **Signing**: cosign keyless (OIDC via GitHub-Actions-Workflow-Identity). Verifikation in Konsumenten-Clustern via Kyverno-ClusterPolicy `image-verify-platform-oci` (siehe [Issue #18](https://github.com/devobagmbh/talos-platform-docs/issues/22)).
- **Werte-Trennung**: cluster-spezifische Helm-Values bleiben in den Consumer-Cluster-Repos. Dieser Layer enthält Defaults und shared values.
- **Sprache**: Deutsch in `README.md` und Doku. Code/Werte folgen Upstream-Konventionen (englisch).
- **Tools**: alle dev-relevanten Binaries kommen aus Devbox — direktes `brew install <tool>` ist verboten, um Versions-Drift zu vermeiden.

## Konsumenten

Consumer-Cluster-Repos (Layer 3) referenzieren die OCI-Komponenten per Tag / Argo `targetRevision` und komponieren daraus ihre Cluster-Konfiguration. Welches Subset ein Consumer konsumiert, lebt im jeweiligen Consumer-Repo, nicht hier.

## Verwandte Doku

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0012 — Platform-Registry-Proxy (Harbor)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-Cluster-Registry (Harbor auf beiden Clustern)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)
- [ADR-0015 — Monitoring-Architektur (LGTM-A)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

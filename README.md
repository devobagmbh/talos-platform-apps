# talos-platform-apps

[![Talos Linux](https://img.shields.io/badge/Talos%20Linux-1.13.0-ff7300?style=flat-square)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36.0-326ce5?style=flat-square&logo=kubernetes)](https://kubernetes.io/)
[![Helm](https://img.shields.io/badge/Helm-v3-0F1689?style=flat-square&logo=helm)](https://helm.sh/)
[![cosign](https://img.shields.io/badge/cosign-2.4%2B-2E7D9A?style=flat-square&logo=sigstore)](https://github.com/sigstore/cosign)
[![ORAS](https://img.shields.io/badge/ORAS-1.2%2B-1E3F66?style=flat-square)](https://oras.land/)
[![syft](https://img.shields.io/badge/syft-SBOM-9059F6?style=flat-square)](https://github.com/anchore/syft)
[![Devbox](https://img.shields.io/badge/Devbox-Nix--based-31135a?style=flat-square)](https://www.jetify.com/devbox/)
[![direnv](https://img.shields.io/badge/direnv-2.36%2B-FFD400?style=flat-square)](https://direnv.net/)
[![Taskfile](https://img.shields.io/badge/Taskfile-v3-29BEB0?style=flat-square&logo=Task)](https://taskfile.dev/)
[![TeamCity](https://img.shields.io/badge/TeamCity-CI-000000?style=flat-square&logo=teamcity)](https://www.jetbrains.com/teamcity/)

OCI-Sub-Layer der Devoba Talos-Plattform: `lifecycle`, `storage-objects`, `registry`, `databases`, `secrets`, `automation`, `dns` und `monitoring`. Vorgerenderte Manifeste mit cosign-Signatur, SLSA-v1-Provenance und CycloneDX-SBOM. Konsumiert von Seeder und DHQ.

## Zweck

Dieses Repo bündelt **gemeinsam genutzte Plattform-Komponenten** (Helm-Charts + Werte + ggf. Custom-Manifeste), rendert sie zu fertigen Manifesten und publiziert sie als signierte OCI-Artefakte. Seeder- und DHQ-Cluster konsumieren diese Layer per Tag (Argo `targetRevision`), nicht per Helm-Render zur Apply-Zeit.

Begründung: deterministische, reviewbare Deployment-Artefakte mit kryptografischer Supply-Chain-Verifikation. Cluster-Update = Tag-Bump in der Konsumenten-Konfiguration. Siehe [ADR-0009](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md).

## Sub-Layer-Übersicht

| Sub-Layer | Inhalt | Konsumiert von | Backlog-Issue |
|---|---|---|---|
| [`automation`](sub-layers/automation/) | Renovate + Velero | DHQ (Renovate), beide (Velero) | #16 |
| [`databases`](sub-layers/databases/) | CNPG-Operator | beide | #15 |
| [`dns`](sub-layers/dns/) | PowerDNS-Auth + External-DNS + cert-manager-DNS01-Issuer | DHQ (Phase 6) | #16a |
| [`lifecycle`](sub-layers/lifecycle/) | Crossplane + Provider + iPXE | Seeder | #12 |
| [`monitoring`](sub-layers/monitoring/) | LGTM-A (Loki + Grafana + Tempo + Mimir + Alloy + kube-prometheus-stack operator-only) | beide | #17 |
| [`registry`](sub-layers/registry/) | Harbor | beide | #14 |
| [`secrets`](sub-layers/secrets/) | ESO + Vault Config-Templates | beide | #15a |
| [`storage-objects`](sub-layers/storage-objects/) | Garage | beide (Seeder + DHQ je eigene Instance, DS720+ als Backup-Ziel) | #13 |

Pro Sub-Layer existiert ein eigenes `README.md` mit Detail-Inhalt und Verweisen auf die entscheidenden ADRs.

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
task render -- monitoring         # rendert sub-layers/monitoring zu rendered/manifest.yaml
task sign   -- monitoring v0.1.0  # cosign sign des publizierten OCI-Tags
task attest -- monitoring v0.1.0  # SBOM + SLSA-Provenance als Attestations
task publish -- monitoring v0.1.0 # render → push → sign → attest in einem Rutsch
task ci                           # lokale Reproduktion des TeamCity-Pipelines
```

### CI

Die produktive Pipeline läuft auf **TeamCity** (`teamcity.devoba.de`, intern). Build-Konfigurationen folgen in einer eigenen Iteration und triggern bei Tag-Push (`<sub-layer>-vX.Y.Z`).

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
- **Signing**: cosign keyless (OIDC via TeamCity-Build-Identity). Verifikation in Konsumenten-Clustern via Kyverno-ClusterPolicy `image-verify-platform-oci` (siehe [Issue #18](https://github.com/devobagmbh/talos-platform-docs/issues/22)).
- **Werte-Trennung**: cluster-spezifische Helm-Values bleiben in den Konsumenten-Repos (`talos-seeder-cluster`, `talos-dhq-cluster`). Dieser Layer enthält Defaults und shared values.
- **Sprache**: Deutsch in `README.md` und Doku. Code/Werte folgen Upstream-Konventionen (englisch).
- **Tools**: alle dev-relevanten Binaries kommen aus Devbox — direktes `brew install <tool>` ist verboten, um Versions-Drift zu vermeiden.

## Konsumenten

- **Seeder** — [`talos-seeder-cluster`](https://github.com/devobagmbh/talos-seeder-cluster): konsumiert `lifecycle`, `registry`, `storage-objects`, `automation` (Renovate), `secrets`, `monitoring` (Subset).
- **DHQ** — [`talos-dhq-cluster`](https://github.com/devobagmbh/talos-dhq-cluster): konsumiert alle 8 Sub-Layer.

## Verwandte Doku

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0012 — Platform-Registry-Proxy (Harbor)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-Cluster-Registry (Harbor auf beiden Clustern)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)
- [ADR-0015 — Monitoring-Architektur (LGTM-A)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0017 — External-DNS-Strategie](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)

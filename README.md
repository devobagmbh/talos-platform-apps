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

OCI sub-layers of the Devoba Talos platform: `automation`, `databases`, `identity`, `lifecycle`, `network`, `observability`, `registry`, `secrets`, `storage-block`, and `storage-objects`. Pre-rendered manifests with cosign signature, SLSA v1 provenance, and CycloneDX SBOM. Consumed by consumer-cluster repos.

## Purpose

This repo is the **central platform catalog** of the Devoba Talos platform: **everything that is not substrate** (does not belong in `talos-platform-base`) lives here as independently versioned, signed OCI artifacts — Helm charts + values + optional custom manifests, pre-rendered in CI into final manifests. **Consumer-cluster repos draw from the catalog** by referencing exactly the OCI components they need (by tag / Argo `targetRevision`, not by Helm render at apply time). Division of labor: **Base = substrate, Apps = catalog, Consumer = composition** — whatever is not substrate belongs in the catalog, never in Base.

Rationale: deterministic, reviewable deployment artifacts with cryptographic supply-chain verification. A cluster update is a tag bump in the consumer configuration. See [ADR-0009](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md).

## Sub-layer and component overview

OCI distribution is **per component** (ADR-0009, revision 2026-05-26). The sub-layer remains a directory grouping and tag namespace.

| Sub-layer | Components | Backlog issue |
|---|---|---|
| [`automation`](sub-layers/automation/) | renovate, velero | #16 |
| [`databases`](sub-layers/databases/) | cnpg | #15 |
| [`identity`](sub-layers/identity/) | dex | #47 |
| [`lifecycle`](sub-layers/lifecycle/) | crossplane, ipxe, providers, compositions | #12 |
| [`network`](sub-layers/network/) | multus-cni-crds | #48 |
| [`observability`](sub-layers/observability/) | kube-prometheus-stack, loki, mimir, tempo, alloy, grafana | #17 |
| [`registry`](sub-layers/registry/) | harbor | #14 |
| [`secrets`](sub-layers/secrets/) | external-secrets, clustersecretstore-defaults | #15a |
| [`storage-block`](sub-layers/storage-block/) | democratic-csi, synology-csi | #50 |
| [`storage-objects`](sub-layers/storage-objects/) | garage, garage-buckets | #13 |

Each sub-layer has a `README.md` with a component table including sync-wave order. Each component has its own `README.md` + `compatibility.yaml` with a `requires` block (component dependencies, including cross-sub-layer ones such as `databases/cnpg` for Harbor).

## Local Setup

The dev environment runs entirely on **Devbox** (Nix-based) + **direnv**. Tool versions are pinned per repo and on `PATH` automatically after `cd` — no global `brew install` needed.

### Prerequisites

| Tool | Version | Installation note |
|---|---|---|
| **Devbox** | ≥ 0.16 | `curl -fsSL https://get.jetify.com/devbox \| bash` |
| **direnv** | ≥ 2.36 | macOS: `brew install direnv`; Linux: distro package. Hook it into your shell (see [direnv.net/docs/hook.html](https://direnv.net/docs/hook.html)) |
| **git** | ≥ 2.40 | already installed |

### Setup

```bash
git clone git@github.com:devobagmbh/talos-platform-apps.git
cd talos-platform-apps
direnv allow
```

`direnv allow` triggers the `.envrc`, which activates Devbox. On first invocation Devbox installs all tools (`helm`, `kubectl`, `cosign`, `oras`, `syft`, `go-task`, `yq`, `jq`, `sops`, `age`) into a reproducible Nix store. Subsequent `cd`s into the repo switch the environment automatically.

### Tools provided by Devbox

See `devbox.json`. Versions are pinned in `devbox.lock` as needed — updates happen in a controlled manner via `devbox update`.

### Tasks (instead of make)

`go-task` replaces make. Tasks are declared in `Taskfile.yml` (lands in a follow-up iteration). Example targets:

```bash
task render -- observability         # renders sub-layers/observability to rendered/manifest.yaml
task sign   -- observability v0.1.0  # cosign sign of the published OCI tag
task attest -- observability v0.1.0  # SBOM + SLSA provenance as attestations
task publish -- observability v0.1.0 # render → push → sign → attest in one go
task ci                           # local reproduction of the GHA pipeline
```

### Local live testing (Talos + ArgoCD)

For end-to-end tests of individual sub-layers (render → OCI push → Argo sync → apply) there is a prod-conformant **Talos** cluster (docker provisioner) — the same substrate as the consumer clusters (Talos nodes, Cilium CNI, Gateway API, kube-proxy off, KubePrism) — with a local OCI registry behind `registry.localhost.direct` (mkcert TLS):

```bash
task local:up                                  # Talos + Cilium + Gateway + ArgoCD + registry bridge
task local:publish -- lifecycle/crossplane 0.0.0-dev  # push the component into the local registry
task local:apply   -- lifecycle 0.0.0-dev      # create the sub-layer's Argo Applications
task local:argo:ui                             # open https://argocd.localhost.direct
task local:down                                # tear everything down
```

Full architecture, endpoints, component details, and troubleshooting: [`local/README.md`](local/README.md).

### CI

The production pipeline runs on **GitHub Actions** (workflows under `.github/workflows/`). Triggers: PRs (render + lint, no push) and tag push `<sub-layer>-vX.Y.Z` (render + OCI push + cosign sign + SBOM/provenance attest). cosign signing is keyless via the GHA OIDC identity.

**Three binding CI rules** for this and all other platform repos:

1. **Devbox cache active**: every job uses `jetify-com/devbox-install-action` with `enable-cache: true`. Tool versions come exclusively from `devbox.json`/`devbox.lock` — no separate `actions/setup-go`/`-helm`/`-kubectl` steps. This makes the CI environment byte-identical to the workstation, and builds are cache-warm after the first run.
2. **Locally reproducible**: every single task in `Taskfile.yml` runs on the workstation exactly as in CI. Before `git push` the full pipeline is replayed locally (`task ci`). No GHA-specific code in tasks — outer logic (OIDC, tag detection, matrix) stays in the workflow.
3. **Pipeline = thin task caller**: workflow steps only call `task <name>`. No inline `helm template`/`oras push`/`cosign sign` commands in the YAML. Whoever wants to change pipeline behavior changes the task — workflow diffs stay minimal and easy to review.

## Render / sign / publish workflow

```
Helm chart + values
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
 syft → CycloneDX SBOM → cosign attest
        │
        ▼
 slsa-github-generator → provenance → cosign attest
```

Pipeline implementation follows in a separate iteration (a task from phase 2 of the [day-zero-backlog](https://github.com/devobagmbh/talos-platform-docs/blob/main/operations/day-zero-backlog.md)).

## Conventions

- **Sub-layer versioning**: SemVer per sub-layer (`<sub-layer>-vMAJ.MIN.PATCH`). Each sub-layer has an independent lifecycle.
- **OCI paths**: `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>:<tag>` as the manifest, same path for SBOM/provenance attestations.
- **Signing**: cosign keyless (OIDC via the GitHub Actions workflow identity). Verification in consumer clusters via the Kyverno ClusterPolicy `image-verify-platform-oci` (see [Issue #18](https://github.com/devobagmbh/talos-platform-docs/issues/22)).
- **Value separation**: cluster-specific Helm values stay in the consumer-cluster repos. This layer holds defaults and shared values.
- **Language**: English throughout — code, comments, READMEs, and docs (platform policy 2026-06-03). Code and Helm values follow upstream conventions (English).
- **Tools**: all dev-relevant binaries come from Devbox — direct `brew install <tool>` is forbidden to avoid version drift.
- **Consumer composition**: consumer-cluster repos (layer 3) reference the OCI components by tag / Argo `targetRevision` and compose their cluster configuration from them. Which subset a consumer uses lives in the respective consumer repo, not here.

## Related docs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0012 — Platform-Registry-Proxy (Harbor)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-cluster registry (Harbor on both clusters)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)
- [ADR-0015 — Monitoring architecture (LGTM-A)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

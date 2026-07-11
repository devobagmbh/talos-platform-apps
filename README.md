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

OCI sub-layers of the Devoba Talos platform: `automation`, `databases`, `identity`, `lifecycle`, `network`, `observability`, `registry`, `secrets`, `storage-block`, and `storage-objects`. Pre-rendered manifests, cosign-signed (keyless); SLSA v1 provenance and CycloneDX SBOM attestations are planned (phase 2+, see `task attest`). Consumed by consumer-cluster repos.

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
| [`observability`](sub-layers/observability/) | prometheus-operator, loki, mimir, tempo, alloy, grafana | #17 |
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
lefthook install   # activate the Git pre-commit / commit-msg hooks (lint, signing, secrets, scope)
```

`direnv allow` triggers the `.envrc`, which activates Devbox. On first invocation Devbox installs all tools (`helm`, `kubectl`, `cosign`, `oras`, `syft`, `go-task`, `yq`, `jq`, `sops`, `age`) into a reproducible Nix store. Subsequent `cd`s into the repo switch the environment automatically.

`lefthook install` wires the local Git hooks (`.git/hooks/`) — **required once per clone** so the pre-commit gates (including the commit-signing check below) actually run; without it an unsigned or non-conforming commit is caught only later on the server.

### Commit signing (required for merge)

`main` enforces **signed commits** (branch protection `required_signatures`). An unsigned commit makes a PR `mergeStateStatus: BLOCKED` even when review and checks are green. The fix is to **sign the commit** — never to admin-override the gate. (This is **git commit signing**, distinct from the **cosign OCI artifact signing** done by CI — see [Render / sign / publish workflow](#render--sign--publish-workflow).)

Configure signing **once, globally** on your machine. Commit signing is a per-developer, per-machine identity setting — a global config then signs commits in **every** repository, **every** fresh clone, and **every** git worktree automatically, so there is no per-repo or per-clone step to remember:

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub   # your PUBLIC key (.pub); adjust if your key has a different name
git config --global commit.gpgsign true
```

> **Note:** `user.signingkey` points at the **public** key (`.pub`), not the private key. Global `commit.gpgsign true` enables signing in **all** your repositories — if you already sign other projects (e.g. with GPG), run the three commands with `--local` inside this clone instead, so your machine-wide `gpg.format`/key are not overwritten.

For the green **Verified** badge three conditions MUST additionally hold on GitHub (these are per-account and cannot be scripted from a repo):

1. The **same** public key is registered as a **Signing key** (Settings → SSH and GPG keys → *New SSH key* → key type **Signing Key**) — a separate entry from the Authentication key, even with identical key material.
2. Your committer email is a **verified** email on that same account.
3. If the key is **passphrase-protected**, it is loaded into the ssh-agent (`ssh-add --apple-use-keychain <key>` on macOS) — otherwise non-interactive / agent-driven commits fail to sign and are rejected.

**Verify** via the GitHub **Verified** badge on a pushed commit (the authoritative check). The local `git log --show-signature -1` additionally needs a configured `gpg.ssh.allowedSignersFile` to print `Good "git" signature`; without it a correctly-signed commit shows as unverifiable locally even though GitHub accepts it.

### Tools provided by Devbox

See `devbox.json`. Versions are pinned in `devbox.lock` as needed — updates happen in a controlled manner via `devbox update`.

### Tasks (instead of make)

`go-task` replaces make. Tasks are declared in `Taskfile.yml`. Example targets:

```bash
task render:one -- lifecycle/crossplane        # render one component to rendered/manifest.yaml
task sign       -- lifecycle/crossplane v0.1.0 # cosign sign of the published OCI tag
task attest     -- lifecycle/crossplane v0.1.0 # SBOM + SLSA provenance (deferred stub, phase 2+)
task publish    -- lifecycle/crossplane v0.1.0 # render → package → push → sign in one go
task ci                                        # local reproduction of the GHA pipeline
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

The production pipeline runs on **GitHub Actions** (workflows under `.github/workflows/`). Triggers: PRs (render + lint, no push) and tag push `<sub-layer>/<component>-vX.Y.Z` (render + OCI push + cosign sign + verify). Tags are normally cut by release-please (see § Release automation); cosign signing is keyless via the GHA OIDC identity (`oci-publish.yml@refs/tags/...`).

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
 task package → <component>-<tag>.tar.gz   (single OCI layer, tar of manifest.yaml)
        │
        ▼
oras push ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>/<component>:<tag>
        │
        ▼
 cosign sign --yes
        │
        ▼
 cosign verify   (keyless; identity oci-publish.yml@refs/tags/...)

 # phase 2+ (deferred — NOT wired in oci-publish.yml today; see `task attest`):
 #   syft → CycloneDX SBOM → cosign attest
 #   slsa-github-generator → provenance → cosign attest
```

### Release automation (release-please)

Releases are automated per component — you do **not** hand-cut tags in the normal flow:

1. Merge a `feat`/`fix` commit that touches exactly one `sub-layers/<sl>/components/<c>/` (the lefthook `lint:commit-scope` gate enforces one component per commit, because release-please maps commits to components by path).
2. `release-please.yml` opens (or updates) a **per-component release PR** that bumps the version and updates the changelog.
3. Merging that release PR cuts the tag `<sub-layer>/<component>-vX.Y.Z`. The tag is created with a **GitHub App installation token** (not the built-in `GITHUB_TOKEN`, whose events do not cascade to other workflows), so the tag-push triggers `oci-publish.yml`, which renders → pushes → signs → verifies the component. The cosign signing identity stays `oci-publish.yml@refs/tags/...` — unchanged for `task verify` and for consumer-side Kyverno verification.

The per-component version SoT is [`.release-please-manifest.json`](.release-please-manifest.json); [`release-please-config.json`](release-please-config.json) enumerates every component (not-yet-implemented stubs carry `initial-version: 0.1.0`); every `components/` directory is a release package — a *stack* like `kube-prometheus-stack` is a composition documented in its sub-layer README, not a `components/` directory.

**One-time setup (org admin).** release-please cuts tags via a GitHub App token (short-lived, minted per run — no long-lived PAT). Create a GitHub App in `devobagmbh` with repo permissions **Contents: Read & Write**, **Pull requests: Read & Write**, **Issues: Read & Write**; **install it on this repository only** (not org-wide — limits the App key's blast radius); then set repo variable `RELEASE_PLEASE_APP_ID` and repo secret `RELEASE_PLEASE_APP_PRIVATE_KEY`. Until `RELEASE_PLEASE_APP_ID` is set the `release-please` job is **skipped** (neutral, no failing check); manual tag push remains available for releases in the meantime.

**Manual / backfill tag** — a hand-pushed `<sub-layer>/<component>-vX.Y.Z` tag also triggers `oci-publish.yml` directly (first-time backfill or a hotfix). Caveat: push **at most three tags per `git push`** — tags beyond the third in a single push raise no workflow run at all (silently), so batch larger backfills.

**Adoption cutover (pre-existing components).** `bootstrap-sha` in `release-please-config.json` marks where release-please starts managing this repo. Component changes merged *before* that SHA are **not** auto-released by the first run — release-please anchors on its own last release PR (or `bootstrap-sha`), never on the manually backfilled tags, and the manifest already records each component's last published version. Pre-cutover unreleased changes are therefore published via the **manual-backfill path above** when a component next warrants a version (`bootstrap-sha`/`last-release-sha` are top-level-only — there is no per-package config alternative). The pending pre-cutover backfill is tracked in issue #259.

**Recovering a stuck release** — if a release PR merged but no OCI artifact appeared, the cut tag did not reach `oci-publish.yml`. Check the [Actions tab](../../actions/workflows/oci-publish.yml) for a run on that tag:

- A run exists but **failed** (e.g. a transient upstream Helm-repo error during render) → re-run it from the Actions UI (*Re-run failed jobs*). No tag change needed.
- **No run** exists (the tag event never fired) → re-push the tag to re-raise the event (`oci-publish.yml` has no `workflow_dispatch`, so a tag re-push is the only trigger). Re-push the tag **at the commit it already points at** (the release PR's merge commit), never at `HEAD`, or a different tree is published — capture that commit *before* deleting the tag, and confirm it is the intended release commit (not a moved or tampered ref) before re-signing:

  ```bash
  rel_sha=$(git rev-list -n 1 <sub-layer>/<component>-vX.Y.Z)  # commit the tag points at — capture FIRST
  git push origin :refs/tags/<sub-layer>/<component>-vX.Y.Z    # delete the remote tag
  git tag -fs <sub-layer>/<component>-vX.Y.Z "$rel_sha"        # re-create at the same commit (signed)
  git push origin <sub-layer>/<component>-vX.Y.Z               # re-push → triggers oci-publish.yml
  ```

  While the tag is deleted, a consumer Argo app pinning it by `targetRevision` sees a transient gap until the re-push lands.

**Rotating the App key** — generate a new private key in the GitHub App's settings, update the repo secret `RELEASE_PLEASE_APP_PRIVATE_KEY` with the new PEM, then delete the old key in the App settings. `RELEASE_PLEASE_APP_ID` is unchanged. Old keys stay valid until deleted, so there is no downtime window.

## Conventions

- **Per-component versioning**: SemVer per component (`<sub-layer>/<component>-vMAJ.MIN.PATCH`). Each component has an independent lifecycle (managed by release-please).
- **OCI paths**: `ghcr.io/devobagmbh/talos-platform-apps/<sub-layer>/<component>:<tag>` as the manifest, same path for SBOM/provenance attestations.
- **Signing**: cosign keyless (OIDC via the GitHub Actions workflow identity). Verification in consumer clusters via the Kyverno ClusterPolicy `image-verify-platform-oci` (see [Issue #21](https://github.com/devobagmbh/talos-platform-docs/issues/21)).
- **Value separation**: cluster-specific Helm values stay in the consumer-cluster repos. This layer holds defaults and shared values.
- **Language**: English throughout — code, comments, READMEs, and docs (platform policy 2026-06-03). Code and Helm values follow upstream conventions (English).
- **Tools**: all dev-relevant binaries come from Devbox — direct `brew install <tool>` is forbidden to avoid version drift.
- **Consumer composition**: consumer-cluster repos (layer 3) reference the OCI components by tag / Argo `targetRevision` and compose their cluster configuration from them. Which subset a consumer uses lives in the respective consumer repo, not here.

## Related docs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0012 — Platform-Registry-Proxy (Harbor)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-cluster registry (Harbor on both clusters)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)
- [ADR-0015 — Monitoring architecture (LGTM-A)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)

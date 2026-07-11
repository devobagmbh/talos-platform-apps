# Local development environment

[![Talos](https://img.shields.io/badge/Talos-v1.13.3-FF7300?style=flat-square&logo=talos)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36.0-326ce5?style=flat-square&logo=kubernetes)](https://kubernetes.io/)
[![Cilium](https://img.shields.io/badge/Cilium-1.19.3-F8C517?style=flat-square&logo=cilium)](https://cilium.io/)
[![Gateway API](https://img.shields.io/badge/Gateway%20API-v1.2-326CE5?style=flat-square&logo=kubernetes)](https://gateway-api.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-9.4-EF7B4D?style=flat-square&logo=argo)](https://argo-cd.readthedocs.io/)
[![cert-manager](https://img.shields.io/badge/cert--manager-1.17-0A6E32?style=flat-square)](https://cert-manager.io/)
[![mkcert](https://img.shields.io/badge/mkcert-Local%20TLS-1F305F?style=flat-square)](https://github.com/FiloSottile/mkcert)
[![Helm](https://img.shields.io/badge/Helm-v3-0F1689?style=flat-square&logo=helm)](https://helm.sh/)
[![Taskfile](https://img.shields.io/badge/Taskfile-v3-29BEB0?style=flat-square&logo=Task)](https://taskfile.dev/)

A prod-shaped **Talos** cluster (docker provisioner) for local sub-layer testing: the same substrate as the consumer clusters — Talos nodes, Cilium CNI, Gateway-API, kube-proxy off, KubePrism in front of the API — plus a local OCI registry with Gateway exposure and mkcert TLS. The full **render → push → Argo-sync → apply** loop runs on the laptop before a tag is pushed to the production OCI path.

## Purpose and design principles

- **Identical to prod where it matters.** This is **Talos**, not kind: real Talos nodes (`ghcr.io/siderolabs/talos:v1.13.3`), `cni: none` + Cilium, kube-proxy disabled, KubePrism on `127.0.0.1:7445`, ArgoCD as the pull-based apply mechanism. What works here works on a consumer cluster, because it *is* the consumer's substrate — not a Kubernetes look-alike.
- **API-driven, immutable config.** Talos has no node shell. The registry mirror, CNI/proxy toggles, and KubePrism all live in the machine config ([`talos-patch.yaml`](talos-patch.yaml)) applied at `talosctl cluster create`, exactly as on a real node — no `docker exec node` containerd hot-patching.
- **No `localhost` hostnames.** Everything runs over `*.localhost.direct` (public DNS wildcard pointing at `127.0.0.1`) with an mkcert wildcard cert, so Argo, the OCI client and the browser behave exactly as they would against a real cluster.
- **Bootstrap without chicken-and-egg.** The OCI backing store is its own Docker container (`kind-registry`), not a pod in the cluster, so the registry exists *before* the cluster lives and Argo can pull artifacts on the first sync. (The `kind-registry` name is historical — it is a plain `registry:2` container, unrelated to the kind binary; the name is kept so cert SANs and the in-cluster Service DNS stay stable.)
- **TLS end-to-end, container to Argo.** The `kind-registry` container terminates TLS itself with an mkcert cert carrying **both** SANs — `localhost` for the workstation and `kind-registry.registry.svc.cluster.local` for intra-cluster pulls. No HTTP bypasses on the Argo/browser path. Argo trusts the mkcert CA via an initContainer in `argocd-repo-server` that appends the CA to the system CA bundle.

## Architecture

```
┌──────────────────────────── Workstation ─────────────────────────────┐
│                                                                      │
│  Browser ───────► https://argocd.localhost.direct                    │
│                   (Cilium Gateway, mkcert wildcard)                  │
│                                                                      │
│  oras push  ────► https://localhost:5001/talos-platform-apps         │
│                   (straight at the container, mkcert SAN: localhost) │
│                                                                      │
└──────────────────────────────│───────────────────────────│───────────┘
                               │ host port 443             │ host port 5001
                               ▼                           ▼
                ┌──────────────────────────────┐    ┌────────────────────┐
                │  Talos node container        │    │  kind-registry     │
                │  (controlplane-1)            │    │  (Docker container)│
                │                              │    │  registry:2 + TLS  │
                │  Cilium Gateway NodePort     │    │  /certs (volume)   │
                │  30443 → Gateway-API         │    └────────┬───────────┘
                │   └─► HTTPRoute argocd       │             │
                │       └─► argocd-server      │             │ docker net "talos-platform-apps"
                │                              │             │ via Service + EndpointSlice
                │  KubePrism 127.0.0.1:7445    │             │
                │   └─► Cilium k8sServiceHost   │             │ cluster pull (Argo):
                │                              │             │ https://kind-registry.registry
                │  registry mirror (machine    │◄────────────┘ .svc.cluster.local:5000
                │   config): localhost:5001 →  │  (mkcert SAN: Service DNS)
                │   https://kind-registry:5000 │
                │                              │
                │  argocd-repo-server          │
                │   • initContainer appends    │
                │     mkcert CA to the system  │
                │     CA bundle                │
                │   • native OCI pull          │
                │     validates the cert chain │
                └──────────────────────────────┘
```

**One container identity, two hostnames, one mkcert CA as the trust anchor.** Workstation and cluster address the same registry container, each via its own hostname SAN. The mkcert CA sits in the workstation system trust (via `mkcert -install`) and in the argocd-repo-server pod (via initContainer + the `mkcert-ca` ConfigMap in the `argocd` namespace).

## Components and manifests

| File | Purpose |
|---|---|
| [`talos-patch.yaml`](talos-patch.yaml) | Talos machine-config patch applied to every node at `talosctl cluster create`: `cluster.network.cni.name: none`, `cluster.proxy.disabled: true`, `allowSchedulingOnControlPlanes: true`, KubePrism `:7445`, and the `localhost:5001 → https://kind-registry:5000` registry mirror (intra-network pull uses `tls.insecureSkipVerify`, matching the old kind containerd hot-patch — the Argo/browser path keeps real mkcert trust). |
| [`cilium-values.yaml`](cilium-values.yaml) | Helm values: `kubeProxyReplacement: true`, `gatewayAPI.enabled: true`, Hubble + Relay, `l2announcements.enabled` for future LB-IPAM. `k8sServiceHost=localhost`/`:7445` is added in the Taskfile as a `--set`. |
| [`mkcert-cluster-issuer.yaml`](mkcert-cluster-issuer.yaml) | `ClusterIssuer mkcert-ca` for cert-manager (CA from `$(mkcert -CAROOT)`). |
| [`gateway.yaml`](gateway.yaml) | Gateway `localhost-direct` with HTTP and HTTPS listeners for `*.localhost.direct` + a wildcard `Certificate` (terminates TLS for the **ArgoCD UI** — the registry push bypasses the Gateway). |
| [`argocd-values.yaml`](argocd-values.yaml) | Headless ArgoCD: `ClusterIP` Service, no Ingress, `--insecure` (the Gateway terminates), Dex/Notifications/ApplicationSet off. **initContainer** appends `mkcert-ca` to the repo-server system CA bundle. **`configs.repositories.kind-registry-local`** registers the native OCI repo (`type: oci`, `oci://` URL) so Argo takes the native-OCI source path (`sourceType=Directory`). |
| [`argocd-route.yaml`](argocd-route.yaml) | `HTTPRoute argocd` → `argocd-server:443` on `argocd.localhost.direct`. |
| [`registry-bridge.yaml`](registry-bridge.yaml) | Namespace `registry` + Service `kind-registry` + a manual `EndpointSlice` with `${KIND_REGISTRY_IP}` (via `envsubst` from `docker container inspect`) — the container speaks TLS directly, no HTTPRoute. |
| [`argo-apps/<sub-layer>/<component>.yaml`](argo-apps/) | Per-component Argo `Application` manifests with `${TAG}` / `${REGISTRY}` placeholders, applied via `task local:apply`. `repoURL` is `oci://${REGISTRY}/<sub-layer>/<component>` + `path: .`, so Argo takes the native OCI source (`sourceType=Directory`) and matches the registered `type: oci` repo. |

## Prerequisites

- **Devbox shell active** for the repo, so `talosctl`, `helm`, `kubectl`, `mkcert`, `argocd`, `kubectx`, `envsubst`, `yq` are on PATH. One-time: `direnv allow` in the repo root (or `devbox shell`). A global `devbox global` is **not** enough — `talosctl` and `mkcert` are pinned in the repo profile only. `task local:up` starts with a preflight that verifies exactly these tools and aborts with a clear hint otherwise.
- Docker Desktop, Colima, Orbstack, or **rootful Podman** running (see *Running on Podman* below for the Podman caveats). The Talos docker provisioner runs the node as a container; the Cilium Gateway is wired via **NodePort + `-p` host-port mappings** — LB-IPAM VIPs are not routable across the Docker NAT on Mac.
- Ports `80` and `443` free on the workstation (no other local HTTP/HTTPS service bound).
- **VM headroom.** The node is created with **8 GiB / 6 CPU** (`--memory-controlplanes`/`--cpus-controlplanes`; override via `LOCAL_NODE_MEMORY` / `LOCAL_NODE_CPUS`). The talosctl default (2 GiB / 2 CPU) is too small — Cilium + ArgoCD + a few platform components (crossplane, cnpg, …) exhaust it and the apiserver starts timing out. These are limits, not reservations, so they fit a smaller VM until actually used; give the Docker/Colima VM enough memory for what you deploy.

### Running on Podman (instead of Docker Desktop)

The `task local:*` flow targets a Docker-Desktop-style daemon. It also works on **Podman**, but the Talos docker provisioner runs the node as a privileged container with nested services, so it **requires a rootful Podman machine** — rootless cannot write `oom_score_adj` / `/proc/sys` kernel params and the node never finishes bootstrapping. Starting from a default (rootless) Podman machine on macOS, four deltas apply:

- **Rootful machine** (the decisive prerequisite): `podman machine set --rootful`, then restart the machine. This is what makes the Talos node bootstrap at all.
- **`DOCKER_HOST`** must point at the Podman socket, because the provisioner talks to it directly: `export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"`. The `/var/run/docker.sock` symlink may resolve to a foreign user's socket and fail with a permission error. **The devbox shell sets this for you** (see *Automatic devbox fallback* below) — the manual export is only needed outside the devbox shell.
- **VM size ≥ 6–8 GiB**: `podman machine set --memory 8192`. The default 2 GiB OOMs once Cilium + ArgoCD + a few components are up (same reason as the VM-headroom note above).
- **Host ports**: the validated run mapped the NodePorts to high host ports (`8080:30080`, `8443:30443`) instead of `80`/`443`, so the Argo/registry endpoints carry the high port. (Binding the privileged `80`/`443` ports was not exercised in this run.)

Docker Desktop, Colima, and Orbstack provision a rootful daemon by default and need none of these. Validated end-to-end on 2026-06-14 (issue #168).

**Automatic devbox fallback.** The devbox `init_hook` removes the two CLI-level deltas: when the shell activates and finds `podman` but **no** working `docker` daemon, it (1) exports `DOCKER_HOST` from `podman machine inspect`, and (2) drops an `exec podman "$@"` shim into the gitignored `.direnv/bin/` and prepends it to `PATH`. This is what makes `task local:*` work even when `docker` is missing or aliased to a wrapper that drops arguments (the classic `Error: missing command 'podman COMMAND'`). It is a strict no-op for anyone with a real `docker` daemon (Docker Desktop / Colima / Orbstack). The shim lives under `.direnv/`, so nothing is committed. **Still manual** (devbox cannot provision the VM): `podman machine set --rootful --memory 8192` plus the machine restart, and the host-port mapping if `80`/`443` are unavailable.

## Quickstart

All in one go:

```bash
task local:up
```

Step order:

1. `local:registry:up` — Docker container `kind-registry` (`registry:2`, anonymous) on `127.0.0.1:5001`, TLS via mkcert
2. `local:cluster:up` — `talosctl cluster create docker` (single schedulable control plane, Talos `v1.13.3`, K8s `1.36.0`, `talos-patch.yaml`), attach the registry to the `talos-platform-apps` docker network, KEP-1755 `local-registry-hosting` ConfigMap
3. `local:gateway-api:install` — standard CRDs `v1.2.0` (before Cilium, so the operator initialises its Gateway-API controller)
4. `local:cilium:install` — Cilium 1.19.3, `k8sServiceHost=localhost:7445` (KubePrism), wait for the CoreDNS rollout
5. `local:storage:install` — local-path-provisioner as the **default StorageClass** (catalog CSIs need the real NAS; local-path is the local stand-in, hostPath under `/var`, namespace PSA-privileged for Talos). Needed for stateful local tests (CNPG, …).
6. `local:cert-manager:install` — cert-manager `v1.17` (Helm, CRDs inline)
7. `local:certs` — `mkcert -install` + `rootCA.pem` as a cert-manager secret + the argocd-NS CA ConfigMap + `ClusterIssuer mkcert-ca`
8. `local:argo:install` — ArgoCD chart 9.4.5 / v3.3.2 (base parity, headless, no Ingress)
9. `local:gateway:apply` — Gateway + wildcard Certificate + ArgoCD HTTPRoute + NodePort patch `30080/30443`
10. `local:registry:bridge` — Service + EndpointSlice with the docker IP of `kind-registry`

Endpoints at the end:

| Endpoint | Address | Use |
|---|---|---|
| Argo UI | `https://argocd.localhost.direct` | Browser login (password: `task local:argo:password`) — TLS via Cilium Gateway + mkcert wildcard |
| Registry push (workstation) | `oci://localhost:5001/talos-platform-apps` | `oras push` from the workstation — TLS straight at the container, mkcert SAN `localhost` |
| Registry pull (cluster) | `kind-registry.registry.svc.cluster.local:5000/talos-platform-apps` | Argo `Application.source.repoURL` (with `oci://` scheme) — TLS at the container, mkcert SAN: Service DNS |

## Push/apply workflow for sub-layers

```bash
# Render, package and push a component to the local registry.
# registry:2 runs anonymous — no oras login required locally. TLS validates against the
# mkcert CA in the system trust (via 'mkcert -install').
task local:publish -- lifecycle/crossplane 0.0.0-dev

# Create the Argo Application(s) of a sub-layer (Argo pulls intra-cluster via the
# Service DNS, matched to the registered kind-registry-local native OCI repo).
task local:apply -- lifecycle 0.0.0-dev

# Sync status
kubectl -n argocd get applications -l platform.devoba.de/sub-layer=lifecycle

# Open the Argo UI
task local:argo:ui
```

`task local:publish` sets `OCI_REGISTRY=localhost:5001/talos-platform-apps` and runs `render:one → package → push`, so the local push path is structurally identical to CI — only the registry host and signing differ.

`task local:apply` fills the per-component Argo `Application` manifests with:

- `${TAG}` = `0.0.0-dev` (chart version, no `v` prefix)
- `${REGISTRY}` = `kind-registry.registry.svc.cluster.local:5000/talos-platform-apps`

Argo pulls the native OCI artifact over the Service DNS (no Gateway round-trip) and applies the pre-rendered `manifest.yaml` directly (`sourceType=Directory`, `path: .`) — no Helm rendering step at reconcile time.

## Live dev loop (`task local:dev`) — Skaffold-style

For active development on **one** component, skip the manual publish/apply round-trip:

```bash
task local:dev -- registry/harbor
```

It does an initial build and then **watches** `sub-layers/<sub-layer>/components/<component>/`. On every save it automatically runs `render → package → push` (local registry, a fresh `0.0.0-dev.<epoch>` tag) and hard-refreshes the component's Argo `Application`; the app's `syncPolicy.automated` then applies the change.

- **Brings up fixtures.** Consumer-owned things the catalog doesn't ship (the actual DB/cache instance + runtime secrets, ADR-0023/0024) come from `local/fixtures/<sub-layer>/<component>/` — CR manifests (e.g. a CNPG `Cluster`) + a `secrets.yaml` whose secrets are **generated at apply time** (no values in the repo; a DB password is copied from CNPG's auto-secret). So `task local:dev -- lifecycle/crossview` first ensures the cnpg operator (dep), then a `crossview-pg` CNPG `Cluster` + the `crossview-db`/`crossview-runtime-secret` secrets, then crossview reaches Healthy. Disable with `LOCAL_DEV_SKIP_FIXTURES=1`. `task local:fixtures -- <comp>` runs it standalone. **Local-only** — in prod these are consumer-owned (the consumer repo). Needs a working StorageClass → `local:up` installs local-path-provisioner (see Quickstart step).
- **`Ctrl-C` tears down.** Skaffold-style: stopping the watcher removes what this component *is* — its Argo `Application`, HTTPRoute, and fixtures (CR instances + generated secrets). Dependency operators (cnpg, crossplane) stay (expensive to redeploy). `LOCAL_DEV_KEEP=1` keeps everything; `task local:down` removes the whole cluster.

- **Fresh tag per iteration.** ArgoCD's repo-server caches the resolved artifact, so re-pushing the *same* mutable tag is not reliably re-pulled. Each save gets a new `0.0.0-dev.<epoch>` tag, which guarantees a clean re-pull — no manual `--hard-refresh`, no tag bookkeeping.
- **No self-trigger.** `rendered/` is gitignored, and `watchexec` honors `.gitignore`, so the render output never re-triggers the watcher.
- **Survives typos.** A broken render mid-edit fails only that one iteration (printed to the console); the watcher keeps running and the next save retries.
- **Requires an Argo-app template** `local/argo-apps/<sub-layer>/<component>.yaml` (template: [`lifecycle/crossplane.yaml`](argo-apps/lifecycle/crossplane.yaml)). `local:dev` errors with a hint if it is missing.
- **Brings up dependencies first.** Before watching, `local:dev` resolves the component's catalog dependencies from its `compatibility.yaml` `requires` (component paths directly; capabilities like `cnpg-postgres` via the providers' `provides[].capabilities[].id`) and deploys each — skipping any that are already `Synced/Healthy`. So `task local:dev -- lifecycle/crossview` first ensures `lifecycle/crossplane` + `databases/cnpg`. Disable with `LOCAL_DEV_SKIP_DEPS=1`.
- **Flags consumer secrets.** It prints the component's required `secret_keys` (from `customization.yaml`) — those are consumer-supplied (e.g. `harbor-runtime-secret`) and are **not** created automatically; without them the workload stays Pending/CrashLoop.
- **Routes web UIs.** If the component has a UI, `local:dev` applies a local `HTTPRoute` from `local/http-routes/<sub-layer>/<component>.yaml` and prints `https://<component>.localhost.direct` (Cilium Gateway + mkcert wildcard). Currently shipped: `lifecycle/crossview`, `registry/harbor`. **Local-only** — in prod the route is consumer-owned (cluster-specific hostname, ADR-0023/0024). Add a route file for another UI component the same way.
- **Patches the public-URL value.** If `local/values-overrides/<sub-layer>/<component>.yaml` exists, it is passed to `helm template` as an extra `--values` at render time (via `EXTRA_VALUES`) so the app's own public-URL config points at the gateway host — harbor `externalURL` and crossview CORS `origin` → `https://<component>.localhost.direct`. **Local-only**: CI/prod never sets `EXTRA_VALUES` and keeps the catalog placeholders (the real value is a consumer Shape-b override, ADR-0023/0024). This is what makes the UI *functional* (redirects/generated links), not just reachable.

`task local:dev:sync -- <sub-layer>/<component>` runs a single iteration (build + push + refresh) without the watcher — useful for a one-off resync. `task local:deps -- <sub-layer>/<component>` prints the resolved dependency order without deploying anything.

## Crossplane composition testing

The Argo loop above tests Helm/manifest components. Crossplane **Compositions** (the XCluster XRD + Composition in `lifecycle/compositions`) get their own loop — they can't use the Argo path because the XCluster composition provisions real clusters via `provider-opentofu` (tofu), which can't run locally.

**Offline render (recommended inner loop)** — the Crossplane analog of `task render`:

```bash
task crossplane:render          # render the XCluster composition against the test XR
task crossplane:dev             # watch + re-render on every save (Skaffold-style)
```

`crossplane render` runs the Composition's function pipeline locally **in Docker** (no cluster, no provisioning) and prints the composed resources — e.g. the `opentofu` `Workspace` the XCluster would create. Inputs:

- `local/crossplane/examples/xcluster-test.yaml` — the test XR (dummy values).
- `local/crossplane/functions.yaml` — the Function packages (versions must match `sub-layers/lifecycle/components/providers/`).
- Override the target with `XR=<file> COMP=<file> task crossplane:render`.

**In-cluster (up to the provider boundary)** — the Argo-style live test:

```bash
task crossplane:apply           # deploy crossplane+providers+compositions, apply the test XR
```

Deploys the lifecycle Crossplane stack to the local Talos cluster (via `local:dev:sync`), applies a dummy `ClusterProviderConfig opentofu-default` (consumer-owned in prod — the catalog only references it by name) and the test XR. It reconciles **up to the provider boundary**: XRD/Composition install, the `XCluster` is `Synced`, the `opentofu` `Workspace` is composed, `provider-opentofu` resolves the config and attempts the tofu module download — which fails as expected on the dummy git source (no real module/backend/hardware locally). This validates the full in-cluster wiring, not actual provisioning.

> The `crossplane:apply` test surfaced two real composition bugs that offline render alone would miss: a string transform missing `type: Format`, and the `Workspace` missing the required `providerConfigRef.kind` for the namespaced opentofu provider.

## Harbor pull-through cache + iPXE Talos boot

End-to-end demo: serve the Talos installer image **through the local Harbor** and have **iPXE** reference it — the local mirror of the prod registry-proxy + PXE-boot flow.

```bash
task local:dev -- registry/harbor   # harbor Healthy (CNPG + Valkey fixtures)
task local:harbor:proxy             # ghcr.io pull-through proxy project in harbor
task local:dev -- lifecycle/ipxe    # ipxe serving the demo boot.ipxe
```

**`task local:harbor:proxy`** (idempotent) creates a Harbor registry endpoint + a `ghcr` **proxy-cache project** → `https://ghcr.io` (ADR-0012). Harbor then caches ghcr pulls on first access — the Talos installer at `harbor.localhost.direct/ghcr/siderolabs/installer:v1.13.3`. Verify the pull-through (Harbor proxies + caches the OCI manifest):

```bash
curl -su admin:<pw> https://harbor.localhost.direct/v2/ghcr/siderolabs/installer/manifests/v1.13.3
```

**iPXE** serves a demo `boot.ipxe` (`local/fixtures/lifecycle/ipxe/`) whose Talos `installer` (`machine.install.image`) points at the harbor-cached image. The boot assets (kernel/initramfs) come from the Talos Image Factory over HTTP; only the OCI installer image flows through harbor. The local boot.ipxe is delivered as a fixture (ConfigMap `ipxe-boot-scripts`); the ipxe Argo app `ignoreDifferences` its `/data` so `selfHeal` doesn't revert it to the catalog placeholder. Inspect it:

```bash
kubectl -n ipxe port-forward svc/ipxe 18080:8080 &
curl -s http://localhost:18080/boot.ipxe          # references harbor.localhost.direct/ghcr/siderolabs/installer
```

Both are **local-only** (proxy project + boot.ipxe): in prod the consumer owns the Harbor proxy config and the real boot scripts (ADR-0012/0023).

## Iteration and cleanup

```bash
# Pause cluster + registry (stop containers, keep state)
task local:stop

# Resume a paused cluster — all workloads come back automatically
task local:start

# Remove a single sub-layer's apps, keep the cluster
task local:remove -- lifecycle

# Full inventory
task local:status

# Reinstall Argo without tearing down the cluster
task local:argo:uninstall && task local:argo:install

# Tear everything down (cluster + registry container)
task local:down
```

> **ArgoCD major-version bump (chart 7.x → 9.x, ArgoCD v2 → v3):** on an *existing* local
> cluster prefer `task local:argo:uninstall && task local:argo:install` (shown above) over a
> bare re-run of `local:argo:install` — a two-major in-place `helm upgrade` updates the
> Application/AppProject CRD schemas under live Applications and can leave a brief
> reconciliation gap. `task local:down && task local:up` is likewise clean; a first-time
> `local:up` is unaffected.

| Task | What happens | State |
|---|---|---|
| `local:stop` | `docker stop` of both containers | kept — on start all workloads return |
| `local:start` | `docker start` + wait for the K8s API | restored from the container FS |
| `local:down` | `talosctl cluster destroy` + `docker rm` the registry | **everything gone** — the next `local:up` is fresh |

`local:stop`/`local:start` is the path for laptop suspend or multi-day pauses without a reinstall. **Do not use it to reset state** — if the cluster gets into a bad state, `local:down && local:up` is the reliable reset, since `talosctl cluster create` provisions a clean cluster.

The mkcert CA stays in the system trust after `local:down` (re-install is idempotent).

## Troubleshooting

**`talosctl cluster create` fails or hangs.**
Check Docker is running and ports 80/443 are free. Inspect the node via the talosconfig under `~/.talos/clusters/talos-platform-apps/`. A full reset is `task local:down && task local:up` (create is not idempotent — the task skips create when `talosctl cluster show` already lists the cluster).

**`talosctl cluster create` skips creation forever after a crashed run.**
A failed create can leave a partial state directory under `~/.talos/clusters/<name>/` with no `state.yaml`. `talosctl cluster destroy` cannot clean it (it needs the state file), and create keeps skipping while the directory exists. Remove it manually — `rm -rf ~/.talos/clusters/talos-platform-apps` — then `task local:up`.

**Wrong kube-context — guard before any `local:apply`.**
`task local:apply` is a `kubectl apply` against the **current** context. When the workstation kubeconfig also holds real (production / consumer) contexts, assert the local one first: `kubectl config current-context` MUST read `admin@talos-platform-apps` before applying. Never run a context-less apply against a shared kubeconfig (tracked in issue #172).

**Cilium hangs on install**, CoreDNS does not start.
Cilium without kube-proxy needs `k8sServiceHost`. On Talos this is KubePrism at `localhost:7445` (machine config). If KubePrism is not up, `talosctl --nodes <ip> service` shows the node services; confirm `cluster.proxy.disabled` and `cni: none` landed (a typo in `talos-patch.yaml` silently falls back to defaults).

**`task local:gateway:apply` hangs on "waiting for cilium-gateway-localhost-direct".**
Cilium creates the Service only after the Gateway is applied. The task polls up to 60s. If it still times out: `kubectl -n gateway describe gateway localhost-direct` shows the real problem (usually missing Gateway-API CRDs or Cilium not ready).

**Browser shows "not trusted" despite mkcert.**
`mkcert -install` puts the CA in the system trust during `task local:certs`. If it misses the browser store (Firefox on Linux has its own): import `~/.local/share/mkcert/rootCA.pem` manually.

**`oras push localhost:5001` fails with a TLS error.**
`task push` sets `--plain-http=false` so oras uses HTTPS against the mkcert-TLS registry (oras would otherwise default a `localhost` ref to plain HTTP → 400). If `mkcert -install` did not carry the trust to the oras binary — happens on Linux when devbox `oras` does not use the system CA bundle — point oras at the mkcert root: `SSL_CERT_FILE=$(mkcert -CAROOT)/rootCA.pem oras push …`.

**Argo `SyncFailed` or `not a valid OCI repository`.**
The `kind-registry-local` repository is not registered or not recognised. Check: `kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repository`. If missing: re-run `helm upgrade argocd … --values local/argocd-values.yaml` (the repo comes from `configs.repositories`). If present but unmatched: confirm the repo registration is `type: oci` with an `oci://` URL, and that the Argo `Application` `repoURL` carries the **`oci://`** scheme with `path: .` (native OCI source, resolves as `sourceType=Directory`).

**Argo Application shows `Unknown`.**
Argo cannot pull the artifact. Check the Service DNS: `kubectl -n registry get endpointslice kind-registry -o yaml` must show an `addresses:` list with the docker IP. If empty: re-run `task local:registry:bridge` (`envsubst` did not resolve `${KIND_REGISTRY_IP}` — `envsubst` from `gettext` must be on PATH, and the registry must be attached to the `talos-platform-apps` docker network).

**`registry.localhost.direct` does not resolve.**
`localhost.direct` is a public wildcard DNS zone resolving everything to `127.0.0.1`. If resolution fails: flush the DNS cache (`sudo dscacheutil -flushcache` on Mac) or check VPN/DNS filters. Last resort, `/etc/hosts`:

```
127.0.0.1  argocd.localhost.direct registry.localhost.direct
```

**Port 80/443 in use.**
`sudo lsof -iTCP -sTCP:LISTEN -P | grep -E ':80 |:443 '` finds the competitor. Often a local nginx, a Docker container, or the AirPlay receiver on Mac.

## Deliberately out of scope

- **No LoadBalancer IPs.** Cilium has `l2announcements.enabled: true` but no `CiliumLoadBalancerIPPool`/`CiliumL2AnnouncementPolicy` — on Mac, LB VIPs are not reachable across the Docker NAT. Routing goes through the NodePort bridge only.
- **No cosign/SBOM signing.** The local publish path renders + packages + pushes; signing and attestation run in CI (`task publish` with GHA OIDC). The local workflow is explicitly "test Helm values", not "validate supply chain".
- **No Dex, no RBAC mapping.** ArgoCD runs with the local admin (`argocd-initial-admin-secret`). Identity federation is a Layer-3 consumer concern.
- **No Velero backup.** Local data is ephemeral by definition.
- **No Cilium-as-inlineManifest.** Cilium is installed post-boot via Helm (easy to tweak `cilium-values.yaml`); the substrate (Talos + `cni: none` + KubePrism) is faithful. Delivering Cilium inside the machine config like `talos-platform-base` does is a possible future tightening.
- **No `qemu` provisioner.** Full-VM local Talos needs KVM/Linux; the docker provisioner is the Mac/Docker-Desktop path.

## Related docs

- [Top `README.md`](../README.md) — repo overview + sub-layers
- [`AGENTS.md`](../AGENTS.md) — conventions (Taskfile rules, Hard Constraints)
- [ADR-0009 — Platform layer model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) — native OCI artifact distribution (§OCI-Artefakt-Form, revised 2026)
- [ADR-0014 — Gateway-API + Cilium for the consumer clusters](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0014-gateway-api.md) — the prod equivalent of this setup

# Local development environment

[![Talos](https://img.shields.io/badge/Talos-v1.13.3-FF7300?style=flat-square&logo=talos)](https://www.talos.dev/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36.0-326ce5?style=flat-square&logo=kubernetes)](https://kubernetes.io/)
[![Cilium](https://img.shields.io/badge/Cilium-1.19.3-F8C517?style=flat-square&logo=cilium)](https://cilium.io/)
[![Gateway API](https://img.shields.io/badge/Gateway%20API-v1.2-326CE5?style=flat-square&logo=kubernetes)](https://gateway-api.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-7.7-EF7B4D?style=flat-square&logo=argo)](https://argo-cd.readthedocs.io/)
[![cert-manager](https://img.shields.io/badge/cert--manager-1.17-0A6E32?style=flat-square)](https://cert-manager.io/)
[![mkcert](https://img.shields.io/badge/mkcert-Local%20TLS-1F305F?style=flat-square)](https://github.com/FiloSottile/mkcert)
[![Helm](https://img.shields.io/badge/Helm-v3-0F1689?style=flat-square&logo=helm)](https://helm.sh/)
[![Taskfile](https://img.shields.io/badge/Taskfile-v3-29BEB0?style=flat-square&logo=Task)](https://taskfile.dev/)

A prod-shaped **Talos** cluster (docker provisioner) for local sub-layer testing: the same substrate as the seeder/office-lab clusters — Talos nodes, Cilium CNI, Gateway-API, kube-proxy off, KubePrism in front of the API — plus a local OCI registry with Gateway exposure and mkcert TLS. The full **render → push → Argo-sync → apply** loop runs on the laptop before a tag is pushed to the production OCI path.

## Purpose and design principles

- **Identical to prod where it matters.** This is **Talos**, not kind: real Talos nodes (`ghcr.io/siderolabs/talos:v1.13.3`), `cni: none` + Cilium, kube-proxy disabled, KubePrism on `127.0.0.1:7445`, ArgoCD as the pull-based apply mechanism. What works here works on the seeder, because it *is* the seeder's substrate — not a Kubernetes look-alike.
- **API-driven, immutable config.** Talos has no node shell. The registry mirror, CNI/proxy toggles, and KubePrism all live in the machine config ([`talos-patch.yaml`](talos-patch.yaml)) applied at `talosctl cluster create`, exactly as on a real node — no `docker exec node` containerd hot-patching.
- **No `localhost` hostnames.** Everything runs over `*.localhost.direct` (public DNS wildcard pointing at `127.0.0.1`) with an mkcert wildcard cert, so Argo, the Helm OCI client and the browser behave exactly as they would against a real cluster.
- **Bootstrap without chicken-and-egg.** The OCI backing store is its own Docker container (`kind-registry`), not a pod in the cluster, so the registry exists *before* the cluster lives and Argo can pull artifacts on the first sync. (The `kind-registry` name is historical — it is a plain `registry:2` container, unrelated to the kind binary; the name is kept so cert SANs and the in-cluster Service DNS stay stable.)
- **TLS end-to-end, container to Argo.** The `kind-registry` container terminates TLS itself with an mkcert cert carrying **both** SANs — `localhost` for the workstation and `kind-registry.registry.svc.cluster.local` for intra-cluster pulls. No HTTP bypasses on the Argo/browser path. Argo trusts the mkcert CA via an initContainer in `argocd-repo-server` that appends the CA to the system CA bundle.

## Architecture

```
┌──────────────────────────── Workstation ─────────────────────────────┐
│                                                                      │
│  Browser ───────► https://argocd.localhost.direct                    │
│                   (Cilium Gateway, mkcert wildcard)                  │
│                                                                      │
│  helm push  ────► https://localhost:5001/talos-platform-apps         │
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
                │   • Helm OCI pull validates  │
                │     the cert chain           │
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
| [`argocd-values.yaml`](argocd-values.yaml) | Headless ArgoCD: `ClusterIP` Service, no Ingress, `--insecure` (the Gateway terminates), Dex/Notifications/ApplicationSet off. **initContainer** appends `mkcert-ca` to the repo-server system CA bundle. **`configs.repositories.kind-registry-local`** registers the OCI Helm repo so Argo takes the OCI code path. |
| [`argocd-route.yaml`](argocd-route.yaml) | `HTTPRoute argocd` → `argocd-server:443` on `argocd.localhost.direct`. |
| [`registry-bridge.yaml`](registry-bridge.yaml) | Namespace `registry` + Service `kind-registry` + a manual `EndpointSlice` with `${KIND_REGISTRY_IP}` (via `envsubst` from `docker container inspect`) — the container speaks TLS directly, no HTTPRoute. |
| [`argo-apps/<sub-layer>/<component>.yaml`](argo-apps/) | Per-component Argo `Application` manifests with `${TAG}` / `${REGISTRY}` placeholders, applied via `task local:apply`. `repoURL` carries no `oci://` scheme so Argo matches the registered Helm OCI repo. |

## Prerequisites

- **Devbox shell active** for the repo, so `talosctl`, `helm`, `kubectl`, `mkcert`, `argocd`, `kubectx`, `envsubst`, `yq` are on PATH. One-time: `direnv allow` in the repo root (or `devbox shell`). A global `devbox global` is **not** enough — `talosctl` and `mkcert` are pinned in the repo profile only. `task local:up` starts with a preflight that verifies exactly these tools and aborts with a clear hint otherwise.
- Docker Desktop (or Colima/Orbstack) running. The Talos docker provisioner runs the node as a container; the Cilium Gateway is wired via **NodePort + `-p` host-port mappings** — LB-IPAM VIPs are not routable across the Docker NAT on Mac.
- Ports `80` and `443` free on the workstation (no other local HTTP/HTTPS service bound).

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
5. `local:cert-manager:install` — cert-manager `v1.17` (Helm, CRDs inline)
6. `local:certs` — `mkcert -install` + `rootCA.pem` as a cert-manager secret + the argocd-NS CA ConfigMap + `ClusterIssuer mkcert-ca`
7. `local:argo:install` — ArgoCD 7.7.0 (headless, no Ingress)
8. `local:gateway:apply` — Gateway + wildcard Certificate + ArgoCD HTTPRoute + NodePort patch `30080/30443`
9. `local:registry:bridge` — Service + EndpointSlice with the docker IP of `kind-registry`

Endpoints at the end:

| Endpoint | Address | Use |
|---|---|---|
| Argo UI | `https://argocd.localhost.direct` | Browser login (password: `task local:argo:password`) — TLS via Cilium Gateway + mkcert wildcard |
| Registry push (workstation) | `oci://localhost:5001/talos-platform-apps` | `helm push` from the workstation — TLS straight at the container, mkcert SAN `localhost` |
| Registry pull (cluster) | `kind-registry.registry.svc.cluster.local:5000/talos-platform-apps` | Argo `Application.source.repoURL` (no `oci://` scheme) — TLS at the container, mkcert SAN: Service DNS |

## Push/apply workflow for sub-layers

```bash
# Render, package and push a component to the local registry.
# registry:2 runs anonymous — no helm registry login. TLS validates against the
# mkcert CA in the system trust (via 'mkcert -install').
task local:publish -- lifecycle/crossplane 0.0.0-dev

# Create the Argo Application(s) of a sub-layer (Argo pulls intra-cluster via the
# Service DNS, matched to the registered kind-registry-local OCI Helm repo).
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

Argo pulls the Helm-chart-wrapper OCI over the Service DNS (no Gateway round-trip), renders it and applies it to the target namespace.

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

**Cilium hangs on install**, CoreDNS does not start.
Cilium without kube-proxy needs `k8sServiceHost`. On Talos this is KubePrism at `localhost:7445` (machine config). If KubePrism is not up, `talosctl --nodes <ip> service` shows the node services; confirm `cluster.proxy.disabled` and `cni: none` landed (a typo in `talos-patch.yaml` silently falls back to defaults).

**`task local:gateway:apply` hangs on "waiting for cilium-gateway-localhost-direct".**
Cilium creates the Service only after the Gateway is applied. The task polls up to 60s. If it still times out: `kubectl -n gateway describe gateway localhost-direct` shows the real problem (usually missing Gateway-API CRDs or Cilium not ready).

**Browser shows "not trusted" despite mkcert.**
`mkcert -install` puts the CA in the system trust during `task local:certs`. If it misses the browser store (Firefox on Linux has its own): import `~/.local/share/mkcert/rootCA.pem` manually.

**`helm push localhost:5001` fails with a TLS error.**
`mkcert -install` did not carry the trust to the helm binary — happens on Linux when devbox `helm` does not use the system CA bundle. Workaround: `SSL_CERT_FILE=$(mkcert -CAROOT)/rootCA.pem helm push …`.

**Argo `SyncFailed: object required` or `not a valid chart repository`.**
The `kind-registry-local` repository is not registered or not recognised. Check: `kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repository`. If missing: re-run `helm upgrade argocd … --values local/argocd-values.yaml` (the repo comes from `configs.repositories`). If present but unmatched: the Argo `Application` `repoURL` must carry **no `oci://` scheme** — otherwise Argo takes the deprecated `--repo oci://…` path.

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
- **No Dex, no RBAC mapping.** ArgoCD runs with the local admin (`argocd-initial-admin-secret`). Identity federation is a Layer-3 office-lab concern.
- **No Velero backup.** Local data is ephemeral by definition.
- **No Cilium-as-inlineManifest.** Cilium is installed post-boot via Helm (easy to tweak `cilium-values.yaml`); the substrate (Talos + `cni: none` + KubePrism) is faithful. Delivering Cilium inside the machine config like `talos-platform-base` does is a possible future tightening.
- **No `qemu` provisioner.** Full-VM local Talos needs KVM/Linux; the docker provisioner is the Mac/Docker-Desktop path.

## Related docs

- [Top `README.md`](../README.md) — repo overview + sub-layers
- [`AGENTS.md`](../AGENTS.md) — conventions (Taskfile rules, Hard Constraints)
- [ADR-0009 — Platform layer model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) — why Helm-chart-wrapper OCI as the distribution format
- [ADR-0014 — Gateway-API + Cilium for office-lab/seeder](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0014-gateway-api.md) — the prod equivalent of this setup

# Component `compute/node-feature-discovery`

[Node Feature Discovery](https://kubernetes-sigs.github.io/node-feature-discovery/)
(NFD) — the kubernetes-sigs node-labeling enabler for the Devoba platform. NFD
detects hardware, kernel, and OS features on each node and exposes them as
`feature.node.kubernetes.io/*` node labels and `NodeFeature` CRs, so feature-aware
consumers can target nodes with `nodeSelector`s.

NFD is an **infrastructure enabler, not a swappable capability**: it underpins the
hardware-dependent compute capabilities (`gpu-runtime`, `vm-runtime`) by labeling
the nodes those workloads schedule onto — but it is not itself an interface a
consumer would swap out independently. It therefore carries **`capabilities: []`**
by design (see [Capability](#capability)).

Helm chart `node-feature-discovery` from
`https://kubernetes-sigs.github.io/node-feature-discovery/charts`, pinned to
**0.18.3** (appVersion **v0.18.3**). This component is **mixed** — a Helm wrapper
plus a `manifests/00-namespace.yaml` (the chart renders no `Namespace`).

## What ships

Three workloads (all chart-enabled by default, all kept):

- **master Deployment** (pod label `role: master`) — the NFD master: reconciles
  `NodeFeature`/`NodeFeatureRule` CRs and writes the node labels.
- **worker DaemonSet** (pod label `role: worker`) — runs on every node; detects
  host features (via hostPath mounts of `/sys`, `/boot`, `/etc/os-release`,
  `/usr/lib`, `/lib`, `/proc/swaps`) and reports them as `NodeFeature` objects.
- **gc Deployment** (pod label `role: gc`) — the garbage collector; prunes stale
  per-node objects (`gc.enable: true` is the chart default).

…plus the chart's RBAC (`ClusterRole`/`ClusterRoleBinding`/`Role`/`RoleBinding`),
`ServiceAccount`s, and ConfigMaps. Object names are deterministic
(`node-feature-discovery-{master,worker,gc}`) via `fullnameOverride`.

Under the **strict-B CRD split** (ADR-0028) the 3 `nfd.k8s-sigs.io` CRDs
(`NodeFeature`, `NodeFeatureRule`, `NodeFeatureGroup`) ship as a **separate**
artifact, [`compute/node-feature-discovery-crds`](../node-feature-discovery-crds/)
at sync-wave **-1** — this workload renders **zero** CRDs (the chart keeps them in
its helm-native `crds/` directory, which `helm template` excludes without
`--include-crds`; `task render:one` renders without that flag) and `requires` that
artifact at `>=v0.1.0`.

Consumer-authored `NodeFeatureRule` CRs (custom labeling rules) are **not** part of
this artifact — they are consumer-owned and live in the consumer cluster repos.

## Freeze-line (ADR-0024)

The **workload** (master/worker/gc Deployments + DaemonSet, RBAC, Namespace) is the
signed, pre-rendered artifact (the CRDs are the companion
[`compute/node-feature-discovery-crds`](../node-feature-discovery-crds/) artifact,
ADR-0028). NFD is **cluster-agnostic at the freeze line**: it needs no
consumer-supplied secrets, config files, env, or selector CRs to run, so
`provided_refs` and every `required.*` list are empty.

**Consumer-owned** (Layer 3), set in the consumer overlay rather than the catalog:

- **Replica count / node placement** — `master.replicaCount`, `nodeSelector`,
  `tolerations` (a cluster property).
- **topologyUpdater** — `topologyUpdater.enable=true` (off in the catalog default;
  enabling it adds a NUMA-topology DaemonSet whose container defaults to root).
- **Prometheus scraping** — `prometheus.enable=true` (off in the catalog default; it
  renders a `monitoring.coreos.com` ServiceMonitor whose CRD is not guaranteed at
  sync-wave 0). **Re-enabling it requires the `monitoring.coreos.com/ServiceMonitor`
  CRD to be Established BEFORE this workload syncs** — wire
  `observability/prometheus-operator-crds` (or the equivalent operator) at an earlier
  sync-wave in the consumer overlay. Enabling `prometheus.enable=true` at sync-wave 0
  without that CRD present makes Argo fail the sync with `no matches for kind
  "ServiceMonitor" in version "monitoring.coreos.com/v1"` — a silent-stuck class, not a
  self-healing transient.
- **NodeFeatureRule CRs** — custom labeling rules the consumer authors in its own
  repo.

## Sync-wave

`0` — the workload (master/worker/gc) starts **after** the `nfd.k8s-sigs.io` CRDs
are established at wave **-1** via
[`compute/node-feature-discovery-crds`](../node-feature-discovery-crds/), so the API
group is registered before the master reconciles any `NodeFeature`/
`NodeFeatureRule` CR.

## Namespace & Pod Security

NFD ships its own `node-feature-discovery` namespace
(`manifests/00-namespace.yaml`) — NFD is the sole catalog occupant (dedicated
namespace), so the Namespace object travels with the artifact and a shipped manifest
wins over Argo `managedNamespaceMetadata`.

**`pod-security.kubernetes.io/enforce: privileged`** — the only PSS level that admits
the worker DaemonSet. The worker mounts hostPath volumes for host feature detection
(`/sys`, `/boot`, `/etc/os-release`, `/usr/lib`, `/lib`, `/proc/swaps`, `features.d`),
architecturally required and not removable. In the Pod Security Standards "HostPath
Volumes" is a **Baseline** control ("hostPath volumes must be forbidden"), so **both**
`baseline` and `restricted` reject a hostPath pod at admission — only `privileged`
admits it. Verified live on a k8s 1.36 cluster: under `enforce: baseline` the worker
is rejected (`violates PodSecurity "baseline:latest": hostPath volumes`); under
`privileged` it is admitted and becomes Ready. A single Namespace carries one enforce
level for all its pods (master/worker/gc share it), so the worker's mandatory hostPath
forces the whole namespace to `privileged`. This matches every node-level hostPath
agent (node-exporter, CSI/CNI node DaemonSets, local-path-provisioner — all
privileged-PSA).

The `privileged` enforce level relies on this being a **dedicated, sole-occupancy**
namespace — its only occupants are the three catalog-owned NFD workloads. Consumers
MUST NOT co-locate other workloads in `node-feature-discovery`: a privileged-enforce
namespace admits any pod (including truly-privileged / host-namespace), so its safety
rests on the dedicated-namespace boundary, not on PSA enforcement.

`audit: restricted` + `warn: restricted` keep the namespace from being a silent
privilege hole: the master and gc pods are restricted-grade (see Defense-in-depth
below) and pass the restricted audit cleanly, while the worker's hostPath usage
surfaces as a **non-blocking** audit entry + apiserver warning. Expect one such warn
per worker pod (one per node) — the known, expected deviation, not a defect; it keeps
any *new* master/gc non-conformance visible even though `enforce: privileged` does not
block it.

**Defense-in-depth, not the PSA backstop.** Each workload's container
`securityContext` is pinned to restricted-grade in `helm/node-feature-discovery.yaml`
(`runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`,
`capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`) — independent of
the namespace enforce level, so the master/gc hardening holds regardless of PSA, and
the worker's seven hostPath mounts are all `readOnly: true`. The operative backstop
against the (disabled) topologyUpdater's root container is the explicit
`topologyUpdater.enable: false` values pin — **not** the namespace PSA label. For the
gc pod the chart hard-codes the **container** securityContext, so its seccompProfile
is set on the gc **pod** securityContext instead (pod-level seccomp applies to every
container).

**Upgrade note.** On a cluster that previously ran this namespace at `enforce:
baseline` (where the worker was rejected), flipping the namespace label alone may not
recover the worker immediately — the DaemonSet controller's `FailedCreate` backoff is
keyed on the DS UID. If the worker stays absent after the namespace syncs, delete the
DaemonSet (`kubectl delete ds node-feature-discovery-worker -n
node-feature-discovery`); Argo (`selfHeal`) recreates it fresh within seconds and it
then admits under `privileged`.

## Capability

`capabilities: []` — **deliberate, api-surface-only, no `# TODO:`**. NFD provides
node-feature labeling, but there is no alternative tool in this catalog a consumer
could swap in to get the same `feature.node.kubernetes.io/*` labels, and
`catalog/capability-index.yaml` carries no `node-labeling` /
`hardware-feature-discovery` capability id. The `gpu-runtime` and `vm-runtime`
capabilities consume NFD's label output indirectly (via `nodeSelector`s in the
consumer overlay), not via a `requires: node-feature-discovery` capability edge.
Precedent: [`compute/kubevirt-cdi`](../kubevirt-cdi/) (an infrastructure member,
not a swappable interface).

## Strict-B consumer wiring (ADR-0028)

This workload requires its CRDs to exist first, so the consumer cluster repo wires
**two** Argo `Application`s:

1. [`compute/node-feature-discovery-crds`](../node-feature-discovery-crds/) at
   `argocd.argoproj.io/sync-wave: "-1"` with
   `argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true`. `Prune=false`
   is the authoritative CR-cascade protection — it stops Argo from deleting a CRD
   (and cascading the live `NodeFeature`/`NodeFeatureRule` CRs) when the source
   removes it; `ServerSideApply=true` clears the 262 KB client-side annotation limit.
2. This **`compute/node-feature-discovery`** workload Application at sync-wave **0**,
   which comes up against CRDs that already exist.

**Version coupling.** The chart pin here (`helm/node-feature-discovery.yaml`
`version: 0.18.3`) and the `compute/node-feature-discovery-crds` vendored-CRD anchor
(also `node-feature-discovery 0.18.3`) MUST be bumped **together** — a chart-version
bump requires re-vendoring the `-crds` manifests in the same change. No mechanical
drift check exists; the coupling is upheld by convention and review (the
`databases/cnpg` precedent).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/node-feature-discovery:node-feature-discovery-vX.Y.Z
```

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

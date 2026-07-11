# Component `compute/nvidia-device-plugin`

[NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin) — the
GPU-scheduling half of the Devoba platform's **nvidia-stack**. The device plugin
runs on every GPU node, discovers the node's NVIDIA GPUs, and advertises them to
the kubelet as the `nvidia.com/gpu` extended resource so that GPU-requesting pods
can be scheduled onto those nodes.

This is the **scheduling** half of the `gpu-runtime` capability. The **telemetry**
half — DCGM GPU metrics for Prometheus — ships separately as
`observability/nvidia-dcgm-exporter` (#61); both halves additively implement the
same `gpu-runtime` capability (see [Capability](#capability)).

Helm chart `nvidia-device-plugin` from
`https://nvidia.github.io/k8s-device-plugin`, pinned to **0.17.4** (appVersion
**0.17.4**). This component is **mixed** — a Helm wrapper plus a
`manifests/00-namespace.yaml` (the chart renders no `Namespace`).

## What ships

Two DaemonSets (both chart-rendered with the default `devicePlugin.enabled: true`):

- **device-plugin DaemonSet** (`<release>-nvidia-device-plugin`) — runs on GPU
  nodes; advertises `nvidia.com/gpu` to the kubelet via the device-plugin socket and
  mounts the host CDI directory. Its default affinity targets nodes carrying the
  NFD-derived labels (`feature.node.kubernetes.io/pci-10de.present`,
  `feature.node.kubernetes.io/cpu-model.vendor_id: NVIDIA`) with a fallback to the
  manual `nvidia.com/gpu.present` label.
- **MPS control-daemon DaemonSet** (`<release>-nvidia-device-plugin-mps-control-daemon`)
  — manages [Multi-Process Service](https://docs.nvidia.com/deploy/mps/) (MPS) shared
  GPU access. It is **dormant by default**: its `nodeSelector` requires
  `nvidia.com/mps.capable: "true"`, so on a cluster without that label it schedules
  zero pods. It is kept rendered (rather than disabled) because it adds no attack
  surface on un-labeled nodes and avoids a values deviation from upstream; its
  containers run `privileged: true` (chart-fixed, required for MPS shared-memory
  management) when it does schedule.

At these values the chart renders **only** these two DaemonSets; together with this
component's `manifests/00-namespace.yaml` the artifact ships the two DaemonSets and the
`nvidia-device-plugin` Namespace — no `ClusterRole`/`ClusterRoleBinding`/`ServiceAccount`
objects (the pods run under the namespace default ServiceAccount).

This component renders **zero** CRDs, so ADR-0028 strict-B does **not** apply —
there is no `-crds` sibling artifact.

The bundled **node-feature-discovery** and **GPU Feature Discovery (GFD)** subcharts
are **disabled** (`nfd.enabled: false`, `gfd.enabled: false`): NFD ships
independently as [`compute/node-feature-discovery`](../node-feature-discovery/), and
using the bundled subchart would deploy a second, conflicting NFD instance at a stale
chart version into the wrong namespace.

## Chart version

Pinned to **0.17.4** deliberately. Chart **0.19.3** introduces
`mps.enableHostPID: true` as a default, which renders `hostPID: true` on the MPS
control-daemon pod — a host-namespace regression this pin avoids (verified by
rendering both versions; 0.17.4 has no `mps.enableHostPID` key and renders no
`hostPID` field). A future chart bump MUST re-evaluate that key (set it to `false`
explicitly, or accept and document the host-PID surface) before moving past 0.17.4.

## Known upstream chart artifacts (0.17.4)

Shipped as-rendered from the upstream chart; documented here so an operator does not
misread them as catalog defects:

- **Identical selectors on both DaemonSets** — the device-plugin and MPS
  control-daemon DaemonSets share the same `matchLabels`
  (`app.kubernetes.io/name` + `instance: nvidia-device-plugin`) and pod-template
  labels. Kubernetes controller ownership stays unambiguous (ownerReferences), but
  label-based targeting (`kubectl -l`, monitors, NetworkPolicies) matches pods of
  **both** DaemonSets — select on the pod-name prefix or container name instead.
- **Dead affinity term** — one of the three OR-joined `nodeSelectorTerms`
  (`feature.node.kubernetes.io/cpu-model.vendor_id: NVIDIA`) never matches real
  hardware (NFD reports Intel/AMD/ARM CPU vendors); GPU-node matching works via the
  `pci-10de.present` and `nvidia.com/gpu.present` terms. Harmless, but do not debug
  scheduling against the vendor_id term.
- **`mps-shm` hostPath without `type:`** — the device-plugin DaemonSet mounts
  `/run/nvidia/mps/shm` with no `type:` field (unlike `mps-root`, which is
  `DirectoryOrCreate`). The path is expected to exist on GPU nodes (created by the
  NVIDIA runtime/driver stack or by the MPS init container on MPS-labelled nodes);
  if a GPU node lacks it, the device-plugin pod can fail with
  `CreateContainerConfigError` until it exists.

## Freeze-line (ADR-0024)

The **workload** (the two DaemonSets and Namespace) is the signed, pre-rendered
artifact. The device plugin is **cluster-agnostic at the freeze line**: it needs no
consumer-supplied secrets, config files, env, or selector CRs to run, so
`provided_refs` and every `required.*` list are empty. It advertises GPUs using its
built-in `fallbackStrategies: ["named", "single"]` when no plugin config is supplied.

**Consumer-owned** (Layer 3), set in the consumer overlay rather than the catalog:

- **Node placement / tolerations** — `nodeSelector`, `tolerations`, and the affinity
  overrides for matching GPU nodes (a cluster property).
- **Plugin config** — `config.name` (an external ConfigMap carrying MIG-strategy /
  shared-access config). Off by default (`config.name: ""`); the plugin starts and
  advertises GPUs without it. A consumer with an existing MIG config wires it in its
  overlay.
- **MPS enablement** — labeling nodes `nvidia.com/mps.capable: "true"` to activate the
  (otherwise dormant) MPS control daemon.

GPU hardware presence and the NVIDIA container runtime / driver on the node are
**Layer-C / base concerns** (the substrate), not this component's: this component
schedules against GPUs the base layer has already made available.

## Consumer obligations

- **Run [`compute/node-feature-discovery`](../node-feature-discovery/)** for automatic
  GPU-node discovery. The device-plugin's default affinity matches the
  `feature.node.kubernetes.io/pci-10de.present` PCI label NFD's worker produces. This
  is a **runtime** coupling (declared in `external_dependencies` +
  `compatibility.yaml` `requires`), not a CRD-ordering one.
- **Fallback without NFD** — a consumer not running NFD MUST manually label GPU nodes
  `nvidia.com/gpu.present: "true"` (the affinity fallback). A consumer running neither
  NFD nor the manual label gets a DaemonSet that never schedules — a
  misconfiguration, not a defect.
- **MPS activation** — labelling a node `nvidia.com/mps.capable: "true"` causes the
  (otherwise dormant) **privileged** MPS control-daemon to schedule onto it
  automatically — no extra sync or Application is needed. MPS-daemon failure or
  eviction tears down **all** shared CUDA contexts on that GPU with no graceful drain,
  so drain MPS clients before removing the label or restarting the daemon.
- **Bootstrap transient** — a transient `CreateContainerConfigError` on
  `/var/lib/kubelet/device-plugins` during node join is **expected** (the device-plugin
  hostPath requires the directory, which the kubelet creates) and self-heals once the
  kubelet initialises — not a config defect.
- **OOM recovery** — if the device-plugin pod is OOM-killed (`OOMKilled` in the pod
  status; the catalog pins a `128Mi` memory limit), the kubelet loses the
  device-plugin socket and removes `nvidia.com/gpu` from the node's **allocatable**
  resources until the DaemonSet pod restarts. Running GPU pods keep their
  allocations; **new** GPU pods fail to schedule (`insufficient nvidia.com/gpu`)
  during that window. Monitor `OOMKilled` events on GPU nodes; the pod restarts
  automatically.

## Sync-wave

`1` — **strictly after** [`compute/node-feature-discovery`](../node-feature-discovery/)'s
wave `0`, so NFD's worker has labelled the GPU nodes before the device-plugin's
affinity evaluates. The consumer Argo `Application` **MUST** preserve this ordering
(any wave strictly higher than NFD's). The device plugin tolerates NFD being present
first and needs no CRD registration (unlike a strict-B component). At the **same**
sync-wave as NFD the device-plugin can evaluate its affinity against the
`feature.node.kubernetes.io/pci-10de.present` labels before NFD has applied them: the
DaemonSet then schedules **zero** pods until NFD catches up — self-healing, but
**unobserved** (no alert distinguishes it from "no GPU nodes present"); wave `1`
avoids that window. The manual `nvidia.com/gpu.present` node label remains the
fallback for a consumer not running NFD
(see [Consumer obligations](#consumer-obligations)).

## Namespace & Pod Security

This component ships its own `nvidia-device-plugin` namespace
(`manifests/00-namespace.yaml`) — it is the sole catalog occupant (dedicated
namespace), so the Namespace object travels with the artifact and a shipped manifest
wins over Argo `managedNamespaceMetadata`.

**`pod-security.kubernetes.io/enforce: privileged`** — the only PSS level that admits
this workload. The device-plugin pod mounts hostPath volumes —
`/var/lib/kubelet/device-plugins` (kubelet device-plugin socket dir),
`/run/nvidia/mps` + `/run/nvidia/mps/shm` (MPS root + shared memory), and
`/var/run/cdi` (Container Device Interface) — all architecturally required and not
removable. In the Pod Security Standards "HostPath Volumes" is a **Baseline** control
("hostPath volumes must be forbidden"), so **both** `baseline` and `restricted` reject
a hostPath pod at admission — only `privileged` admits it. The MPS control-daemon
additionally runs `privileged: true` containers (also Baseline-forbidden). A single
Namespace carries one enforce level for all its pods, so the device-plugin's mandatory
hostPath forces the whole namespace to `privileged`. This matches every node-level
hostPath/privileged agent (node-exporter, CSI/CNI node DaemonSets,
[`compute/node-feature-discovery`](../node-feature-discovery/) — all privileged-PSA).

The `privileged` enforce level relies on this being a **dedicated, sole-occupancy**
namespace — its only occupants are the two catalog-owned device-plugin workloads.
Consumers MUST NOT co-locate other workloads in `nvidia-device-plugin`: a
privileged-enforce namespace admits any pod (including truly-privileged /
host-namespace), so its safety rests on the dedicated-namespace boundary, not on PSA
enforcement.

`audit: restricted` + `warn: restricted` keep the namespace from being a silent
privilege hole: the device-plugin container is restricted-leaning (see Defense-in-depth
below), so its hostPath usage surfaces as a **non-blocking** audit entry + apiserver
warning, keeping any *new* non-conformance visible even though `enforce: privileged`
does not block it.

**Defense-in-depth, not the PSA backstop.** The device-plugin container
`securityContext` is pinned to `allowPrivilegeEscalation: false` +
`capabilities.drop: [ALL]` in `helm/nvidia-device-plugin.yaml` (the chart helper's
verbatim-replacement branch) — independent of the namespace enforce level.
`runAsNonRoot` and `readOnlyRootFilesystem` are **not** pinned: the plugin writes a
Unix socket under the `/var/lib/kubelet/device-plugins` hostPath, accesses the NVIDIA
device nodes, and is expected to run as root; the chart exposes no values key to set
them independently of the full `securityContext` block (a documented design
limitation for a device-driver agent, not a deferral). The MPS control-daemon's
`privileged: true` is chart-fixed and required for MPS operation — not removable.

## Capability

`capabilities: [{id: gpu-runtime, swap_class: rewrite-required}]`. This component is
the **scheduling** half of the active `nvidia-stack` implementation of `gpu-runtime`;
the telemetry half `observability/nvidia-dcgm-exporter` (#61) additively declares the
same `{id: gpu-runtime, swap_class: rewrite-required}`. `nvidia-stack =
nvidia-device-plugin + nvidia-dcgm-exporter` is a deliberate two-component
implementation of one `catalog/capability-index.yaml` entry — the index comment
documents the component-location split (device-plugin in `compute`, dcgm-exporter in
`observability`) as expected, not a duplicate. `swap_class: rewrite-required` reflects
that swapping NVIDIA GPU scheduling for an alternative (AMD ROCm, Intel GPU plugin)
requires consumer CRs and configuration to be rewritten; the index entry's
`single_impl: true` confirms there is no realistic swap candidate today.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/compute/nvidia-device-plugin:nvidia-device-plugin-vX.Y.Z
```

## Related ADRs

- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0021 — Capability-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
  — context only; this component renders no CRDs, so strict-B does not apply.

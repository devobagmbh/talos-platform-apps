# Sub-layer `compute`

VM runtime, GPU scheduling, and hardware-feature detection — a capability-first
bundle with no single CNCF category (talos-platform-docs taxonomy #16, epic #49).
The OCI distribution unit is the component; this directory is the organisational
bracket (ADR-0009).

## Components

| Component | sync-wave | Purpose |
|---|---|---|
| [`kubevirt-crds`](components/kubevirt-crds/) | -1 | Strict-B CRD half (ADR-0028) — the KubeVirt operator-config `CustomResourceDefinition` (`kubevirts.kubevirt.io`). Lands before its workload counterpart. |
| [`kubevirt`](components/kubevirt/) | 0 | Strict-B workload half — the virt-operator (Deployment, RBAC, Services, PriorityClass), the `kubevirt` Namespace (PSA `privileged`), and the `KubeVirt` CR; provides `vm-runtime`. Requires `kubevirt-crds`. |
| [`kubevirt-cdi-crds`](components/kubevirt-cdi-crds/) | -1 | Strict-B CRD half (ADR-0028) — the CDI operator-config `CustomResourceDefinition` (`cdis.cdi.kubevirt.io`, cluster-scoped). Lands before its workload counterpart. |
| [`kubevirt-cdi`](components/kubevirt-cdi/) | 0 | Strict-B workload half — the CDI operator (Deployment, RBAC), the `cdi` Namespace (PSA `restricted`), and the `CDI` operator-config CR. Requires `kubevirt-cdi-crds`. |
| [`node-feature-discovery-crds`](components/node-feature-discovery-crds/) | -1 | Strict-B CRD half (ADR-0028) — the 3 node-feature-discovery `CustomResourceDefinition`s (`nfd.k8s-sigs.io`: `NodeFeature`, `NodeFeatureRule`, `NodeFeatureGroup`). Lands before its workload counterpart. |
| [`node-feature-discovery`](components/node-feature-discovery/) | 0 | Strict-B workload half — the NFD master Deployment + worker DaemonSet + gc Deployment, the `node-feature-discovery` Namespace (PSA `privileged` — the worker DaemonSet mounts hostPath, which both `baseline` and `restricted` forbid); api-surface-only, no capability (hardware-feature labeling enabler for `gpu-runtime`/`vm-runtime`). Requires `node-feature-discovery-crds`. |
| [`nvidia-device-plugin`](components/nvidia-device-plugin/) | 0 | GPU device-plugin (the `nvidia-device-plugin` DaemonSet advertising GPUs to the kubelet) + a dormant MPS control-daemon DaemonSet, the `nvidia-device-plugin` Namespace (PSA `privileged` — the device-plugin mounts hostPath, which both `baseline` and `restricted` forbid); provides `gpu-runtime` (the scheduling half of `nvidia-stack`; the telemetry half `nvidia-dcgm-exporter` ships from `observability`, #61). Renders 0 CRDs (no strict-B split). Requires `node-feature-discovery` at runtime (node-affinity labels). |

## Notes

- **VM runtime** (`vm-runtime`) is delivered by the KubeVirt strict-B pair
  (`kubevirt-crds` sync-wave -1 + `kubevirt` sync-wave 0). **CDI** (Containerized
  Data Importer) is the companion data-import component of the same `vm-runtime`
  app, itself a strict-B pair: `kubevirt-cdi-crds` (sync-wave -1) + `kubevirt-cdi`
  (sync-wave 0). The consumer wires each `-crds` Argo Application first
  (`Prune=false`, `ServerSideApply=true`), then its workload.
- **Hardware prerequisites** for VM runtime (`vt-x`/`amd-v`, the KVM kernel module)
  are a substrate-layer concern (base), not a catalog deliverable — consumers gate
  scheduling on the nodes that carry them.
- **Hardware-feature labeling** is delivered by the **node-feature-discovery**
  strict-B pair (`node-feature-discovery-crds` sync-wave -1 + `node-feature-discovery`
  sync-wave 0). NFD labels nodes (`feature.node.kubernetes.io/*`) so GPU/VM-runtime
  consumers can nodeSelect on hardware features; it is an enabler, not itself a
  swappable capability.
- **GPU scheduling** (`gpu-runtime`) is delivered by **nvidia-device-plugin**
  (sync-wave 0): the device-plugin DaemonSet advertises GPUs to the kubelet, plus a
  dormant MPS control-daemon (scheduled only on nodes labelled
  `nvidia.com/mps.capable`). It is the scheduling half of the `nvidia-stack`
  implementation; the telemetry half (`nvidia-dcgm-exporter`) ships from the
  `observability` sub-layer (#61). The device-plugin's node affinity targets
  NFD-derived labels (`feature.node.kubernetes.io/pci-10de.present`), so the consumer
  wires its Argo Application at a sync-wave strictly after node-feature-discovery.

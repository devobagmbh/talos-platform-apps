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
- The sub-layer also brackets the GPU/hardware axis (node-feature-discovery,
  nvidia-device-plugin per epic #49); those components land as they are built.

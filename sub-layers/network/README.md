# Sub-layer `network`

Secondary pod-network attachment for the Talos platform catalog. The primary CNI
(Cilium) is substrate and lives in `talos-platform-base`; this sub-layer adds the
**multi-NIC add-on** so pods can attach to additional networks beyond the default
eBPF dataplane.

OCI distribution per component (ADR-0009). A consumer cluster references only the
components it needs by tag.

## Capability

| Capability | Implementation | swap-class |
|---|---|---|
| [`secondary-network-attachment`](../../catalog/capability-index.yaml) | Multus CNI (meta-plugin / thin DaemonSet) | `rewrite-required` |

`secondary-network-attachment` is a `single_impl` capability — Multus is the
de-facto solo implementation. Swapping it would require rewriting all consumer
`NetworkAttachmentDefinition` CRs and pod annotations, hence `rewrite-required`.

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`multus-cni-crds`](components/multus-cni-crds/) | -1 | Raw manifest — `NetworkAttachmentDefinition` CRD from upstream `k8snetworkplumbingwg/multus-cni` (strict-B CRDs artifact, ADR-0028) | `oci://.../network/multus-cni-crds:vX.Y.Z` |

Wave -1: `multus-cni-crds` — the `k8s.cni.cncf.io` `NetworkAttachmentDefinition`
CRD lands before any controller or consumer CR (strict-B, ADR-0028). The consumer
wires the `-crds` Argo Application with `Prune=false` (+ `ServerSideApply=true`)
so removing the workload never cascade-deletes live NAD CRs — see
[`components/multus-cni-crds/`](components/multus-cni-crds/).

The **`multus-cni` workload** (sync-wave 0 — the thin Multus DaemonSet that
implements `secondary-network-attachment`) is delivered by its own PR (issue #53)
and extends this table when it lands; it depends on `multus-cni-crds`.

## Consumed by

A consumer cluster that runs workloads needing more than the default pod
interface (e.g. dedicated storage, management, or provider networks) deploys the
`multus-cni-crds` + `multus-cni` pair and authors `NetworkAttachmentDefinition`
CRs (consumer config, not catalog).

## Backlog issues

- [#48 — epic(network): catalog sub-layer build tracking](https://github.com/devobagmbh/talos-platform-apps/issues/48)
- [#53 — feat(network/multus-cni): build catalog component](https://github.com/devobagmbh/talos-platform-apps/issues/53)
- [#16 — taxonomy decision: 5 new sub-layers](https://github.com/devobagmbh/talos-platform-apps/issues/16)

## Related ADRs

- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0028 — Strict-B CRD management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)

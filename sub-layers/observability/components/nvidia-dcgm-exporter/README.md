# Component `observability/nvidia-dcgm-exporter`

[dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter) — the NVIDIA **DCGM
GPU-metrics exporter** (the `DCGM_FI_*` series: GPU utilization, memory, power,
temperature, SM clocks, ECC errors, …). It runs as a per-GPU-node DaemonSet,
reads the NVIDIA DCGM backend on the node plus the kubelet pod-resources socket
(to attribute GPU usage to pods/containers), and exposes the metrics on a
Prometheus `/metrics` endpoint. It does not store or alert; it is a stateless
node-local exporter that the cluster's scraper (Grafana Alloy / Prometheus)
collects. Published as an independently versioned OCI artifact (ADR-0009).

This component implements the **telemetry facet** of the `nvidia-stack`
`gpu-runtime` capability (`compatibility.yaml`
`provides[].capabilities: [{id: gpu-runtime, swap_class: rewrite-required}]`). The
`nvidia-stack` implementation has two facets: the **scheduling** facet is the
sibling `nvidia-device-plugin` (compute sub-layer, which advertises GPUs to the
kubelet), and this component is the **telemetry** facet (which exports their
metrics). Both facets map to the single `gpu-runtime` capability in
`catalog/capability-index.yaml`; the component-location split (device-plugin in
`compute`, this exporter in `observability` as a CNCF "Monitoring" exporter) is
orthogonal to the capability axis (decision #16, issue #61).

## Contents

A `kind: helm` wrapper over the `dcgm-exporter` chart
(`https://nvidia.github.io/dcgm-exporter/helm-charts`, version `4.8.2`, appVersion
`4.8.2`) plus `manifests/00-namespace.yaml`. The rendered workload
(`grep '^kind:' rendered/manifest.yaml`) is:

- `DaemonSet` (`dcgm-exporter`) — one pod per GPU node, **not** a Deployment.
- `Service` (`dcgm-exporter`, ClusterIP) exposing the `/metrics` endpoint.
- `ServiceAccount` (`dcgm-exporter`).
- A `ConfigMap` (`exporter-metrics-config-map`) carrying the DCGM metrics field
  selection (the chart's `fullnameOverride` does **not** rename this ConfigMap).
- chart RBAC (`Role`/`RoleBinding`, and `ClusterRole`/`ClusterRoleBinding` where
  the chart ships them).
- A dedicated `nvidia-dcgm-exporter` `Namespace` (the chart ships none).

The image is pinned to the chart's appVersion
(`nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2-distroless`) — never `:latest`. The
render contains **zero** `CustomResourceDefinition` and **no**
`ServiceMonitor`/`PrometheusRule` (the chart's `serviceMonitor.enabled` toggle —
default `true` — is pinned `false`; see below).

## Host access (essential, intentional)

A DCGM exporter is useless without host access — it can only produce the
`DCGM_FI_*` series by reading the node's NVIDIA DCGM backend and correlating it
with the kubelet. The rendered DaemonSet pod therefore carries (verified against
`rendered/manifest.yaml`):

- `securityContext.capabilities.add: ["SYS_ADMIN"]` — required for DCGM device
  access on the node.
- `runAsNonRoot: false` / `runAsUser: 0` — the chart default; the exporter runs as
  root for device access.
- a `hostPath` volume mounting `/var/lib/kubelet/pod-resources` — the kubelet
  pod-resources socket, used to attribute GPU metrics to the consuming
  pods/containers.

## Resources

The chart pins requests (cpu `100m` / memory `128Mi`) and limits (cpu `200m` /
memory `512Mi`), so the pod runs Burstable rather than BestEffort — left at the
chart defaults.

## Namespace & Pod Security

The component ships a dedicated `nvidia-dcgm-exporter` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule, ADR-0032) carrying
`pod-security.kubernetes.io/enforce: privileged` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`privileged` is **derived** from the rendered workload, not assumed: the DaemonSet
pod uses Baseline-forbidden field classes — `capabilities.add: ["SYS_ADMIN"]`,
`runAsUser: 0`, and a `hostPath` volume (`/var/lib/kubelet/pod-resources`).
"Capabilities" (beyond the Baseline allow-list) and "HostPath Volumes" are
**Baseline** PSS controls, so both `baseline` AND `restricted` reject this pod;
`privileged` is the only level that admits it (precedent:
`observability/node-exporter` and `storage-block/synology-csi`, also privileged
for host access). Declaring `baseline`/`restricted` here would be an
admission-reject footgun caught by `task scan:psa-conformance`.

The catalog ships **only** the `enforce` level and the ownership labels.

## Consumer obligations (out of scope here)

The **consumer** adds the following in its Argo overlay — this catalog component
ships none of them:

- **GPU-node nodeSelector** — the chart default node placement is empty, so the
  DaemonSet would otherwise spread to **all** nodes. On a non-GPU node the pod
  starts but emits no metrics (no NVIDIA GPU / DCGM backend present). The consumer
  MUST add a nodeSelector matching its GPU nodes (e.g. a GPU-feature-discovery
  label) in its overlay so the DaemonSet lands only on GPU nodes.
- **Control-plane toleration** — the catalog default does **not** tolerate
  control-plane taints (`tolerations: []` pins out the chart default, which would
  tolerate `node-role.kubernetes.io/control-plane:NoSchedule`). This GPU exporter
  targets GPU **worker** nodes; control-plane nodes carry no GPU/DCGM backend. A
  consumer that actually runs GPUs on control-plane nodes adds the appropriate
  toleration via its overlay (alongside the GPU-node nodeSelector above).
- **`runtimeClassName: nvidia`** — if the cluster does **not** run the NVIDIA
  GPU-operator (which injects the runtime class automatically), the consumer adds
  `runtimeClassName: nvidia` via overlay so the pod gets the NVIDIA container
  runtime.
- **GPU driver / DCGM backend** — the NVIDIA GPU, driver, and DCGM backend on the
  node are a **Layer-C hardware/substrate precondition** (NVIDIA GPU + driver),
  NOT shipped here. Without them the exporter has nothing to read.
- **Scrape configuration** — the `ServiceMonitor` is **disabled** in the catalog
  default (`serviceMonitor.enabled: false`); the consumer wires scraping
  (Alloy / Prometheus) against the rendered `/metrics` `Service` endpoint via its
  own config (ADR-0024 / #183), so this artifact ships no CRD-typed object.
- **Namespace overlay** (Argo `managedNamespaceMetadata` or a patch on the shipped
  Namespace): the `pod-security.kubernetes.io/enforce-version` pin (its cluster's
  Kubernetes minor), the `audit`/`audit-version` and `warn`/`warn-version` modes,
  and the PNI trust-anchor labels.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Sync-wave

`0` — catalog default. nvidia-dcgm-exporter has no catalog-internal dependencies
and needs only host access plus the GPU substrate, so it deploys early (like
`observability/node-exporter`). A consumer needing it earlier deploys it in an
earlier wave from its own overlay.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/nvidia-dcgm-exporter:0.1.0
```

OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is
`observability/nvidia-dcgm-exporter-v0.1.0` (kept distinct — registry tag vs.
SemVer git tag).

## Related ADRs

- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0032 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0032-catalog-namespace-psa-ownership.md)
- [ADR-0028 — Strict-B CRD management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — N/A here (the chart ships no CRDs; the ServiceMonitor is disabled).
- [ADR-0021 — Capability Layer Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

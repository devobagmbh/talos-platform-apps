# Component `observability/node-exporter`

[node-exporter](https://github.com/prometheus/node_exporter) — the Prometheus
**host/node metrics exporter** (the `node_*` series: CPU, memory, disk I/O,
filesystem, network, load, hwmon, …). It runs as a per-node DaemonSet, reads the
host's `/proc`, `/sys` and root filesystem, and exposes the metrics on a
Prometheus `/metrics` endpoint (port `9100`). It does not store or alert; it is a
stateless node-local exporter that the cluster's **Grafana Alloy** scrapes
(`observability/alloy`). Published as an independently versioned OCI artifact
(ADR-0009).

This component provides **no swappable capability** (`compatibility.yaml`
`provides[].capabilities: []`). node-exporter is the canonical, sole provider of
the `node_*` host metrics over a Prometheus `/metrics` endpoint — there is no
drop-in alternative implementing the same interface, so it is an api-surface-only
component (precedent: `lifecycle/providers`). It is distinct from
`observability/alloy`, which implements the `metrics-scrape` capability (the
*scraper*); node-exporter is the *source* being scraped, complementary to
`observability/kube-state-metrics` (which sources the `kube_*` object-state
series).

## Contents

A `kind: helm` wrapper over the `prometheus-node-exporter` chart
(`https://prometheus-community.github.io/helm-charts`, version `4.55.0`,
appVersion `1.11.1`) plus `manifests/00-namespace.yaml`. The rendered workload
(`grep '^kind:' rendered/manifest.yaml`) is:

- `DaemonSet` (`node-exporter`) — one pod per node, **not** a Deployment.
- `Service` (`node-exporter`, ClusterIP, port `9100`).
- `ServiceAccount` (`node-exporter`, with `automountServiceAccountToken: false` —
  node-exporter needs no API-server access).
- A dedicated `node-exporter` `Namespace` (the chart ships none).

The render is **single-container** — the optional `kube-rbac-proxy` sidecar is
kept at its chart default (`kubeRBACProxy.enabled: false`). The image is pinned to
the chart's appVersion (`quay.io/prometheus/node-exporter:v1.11.1`) — never
`:latest`. The render contains **zero** `CustomResourceDefinition` and **no**
`ServiceMonitor`/`PrometheusRule` (see below).

## Host access (essential, intentional)

A node exporter is useless without host access — it can only produce the `node_*`
series by reading the node itself. The rendered DaemonSet pod therefore carries
(verified against `rendered/manifest.yaml`):

- `hostPID: true` — the host process-ID namespace.
- `hostNetwork: true` — the chart default; node-exporter listens on the host
  network so the metrics endpoint is reachable per-node.
- three **read-only** `hostPath` volumes mounted under `/host/*`: `proc` → `/proc`,
  `sys` → `/sys`, `root` → `/` (with `mountPropagation: HostToContainer`), driving
  the exporter's `--path.procfs` / `--path.sysfs` / `--path.rootfs` args.

These are read-only host mounts and host namespaces; node-exporter writes nothing
to the host.

Because `hostNetwork: true`, the container binds host port `9100` directly on the
node network stack (the rendered spec declares no `hostPort:` — with host
networking the container port *is* the host port). If another process already
occupies port `9100` on a node, that node's DaemonSet pod will `CrashLoopBackOff`
with a bind error while pods on other nodes stay healthy — a per-node partial
failure. Consumers SHOULD confirm no host-level port-`9100` conflict before
deploying (or, if the scraper reaches the pods via the ClusterIP `Service` rather
than per-node IPs, set `hostNetwork: false` in the consumer overlay to remove the
node-IP exposure entirely).

## Security posture (pinned explicitly)

Despite the privileged namespace (forced by the host access above), the
**container** securityContext is pinned as tight as the chart allows so a future
chart bump cannot silently weaken it. Note the chart's value key names:

- Pod-level key is `securityContext:` (NOT `podSecurityContext:`) —
  `runAsNonRoot: true`, `runAsUser: 65534`, `runAsGroup: 65534`, `fsGroup: 65534`.
- Container-level key is `containerSecurityContext:` —
  `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]`, plus `runAsNonRoot: true` + `runAsUser: 65534` (the
  chart omits these at container scope, so they are added explicitly so every
  rendered container runs as non-root nobody with all capabilities dropped).

Least-privilege at the container scope is independent of the namespace PSA level —
the privileged namespace admits the host fields; the container itself stays
unprivileged.

## Namespace & Pod Security

The component ships a dedicated `node-exporter` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule, ADR-0032) carrying
`pod-security.kubernetes.io/enforce: privileged` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`privileged` is **derived** from the rendered workload, not assumed: the DaemonSet
pod uses three Baseline-forbidden field classes — `hostNetwork: true`,
`hostPID: true`, and three `hostPath` volumes (`/proc`, `/sys`, `/`). "Host
Namespaces" and "HostPath Volumes" are **Baseline** PSS controls, so both
`baseline` AND `restricted` reject this pod; `privileged` is the only level that
admits it (precedent: `storage-block/synology-csi`, also privileged for host
access). Declaring `baseline`/`restricted` here would be an admission-reject
footgun caught by `task scan:psa-conformance`.

The catalog ships **only** the `enforce` level and the ownership labels.

## Consumer obligations (out of scope here)

Per ADR-0032, the **consumer** adds the following in its Argo overlay — this
catalog component ships none of them:

- **Namespace** (Argo `managedNamespaceMetadata` or a patch on the shipped
  Namespace): the `pod-security.kubernetes.io/enforce-version` pin (its cluster's
  Kubernetes minor), the `audit`/`audit-version` and `warn`/`warn-version` modes,
  and the PNI trust-anchor labels.
- **Scrape configuration** — Alloy scrapes the `/metrics` endpoint via its own
  config; no `ServiceMonitor`/`PodMonitor` CR is shipped here. Shipping a
  `ServiceMonitor` is a consumer-overlay concern (ADR-0024 / #183), and the chart's
  `prometheus.monitor.enabled` toggle is pinned `false` so this artifact ships no
  CRD-typed object.
- **Placement tweaks** — tolerations for tainted nodes, nodeSelector overrides, and
  HA/topology are consumer-overlay concerns (cluster-specific per AGENTS.md §Hard
  Constraints); the catalog leaves them at the chart defaults (runs on every Linux
  node, tolerates `NoSchedule`). The shipped DaemonSet carries **only** an
  `effect: NoSchedule, operator: Exists` toleration — a node tainted `NoExecute`
  (e.g. an unhealthy or cordoned-for-eviction node) will evict the pod and leave a
  gap in that node's `node_*` series precisely when node health matters most. A
  consumer needing metrics from `NoExecute`-tainted nodes adds the matching
  toleration in its overlay.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Sync-wave

`0` — catalog default. node-exporter has no catalog-internal dependencies and
needs only host access, so it deploys early (like `observability/kube-state-metrics`).
A consumer needing it earlier at bootstrap deploys it in an earlier wave from its
own overlay.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/node-exporter:0.1.0
```

OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is
`observability/node-exporter-v0.1.0` (kept distinct — registry tag vs. SemVer git
tag).

## Related ADRs

- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0032 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0032-catalog-namespace-psa-ownership.md)
- [ADR-0028 — Strict-B CRD management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — N/A here (the chart ships no CRDs; the ServiceMonitor is disabled).
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

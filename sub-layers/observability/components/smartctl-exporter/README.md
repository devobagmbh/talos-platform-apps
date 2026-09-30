# Component `observability/smartctl-exporter`

[smartctl_exporter](https://github.com/prometheus-community/smartctl_exporter) is the
Prometheus **disk SMART health exporter**. It emits the `smartctl_*` series: every ATA
attribute (normalized and raw), the NVMe health log (percentage used, media errors,
critical warning, available spare), the drive's overall verdict, and smartctl's exit
status per device.

- It runs as a per-node DaemonSet. It finds the node's disks with `smartctl --scan`
  and reads each one with `smartctl --json`.
- It exposes the result on a Prometheus `/metrics` endpoint (container port `9633`).
- It does not store or alert.

Published as an independently versioned OCI artifact (ADR-0009).

The component provides **no swappable capability** (`compatibility.yaml`
`provides[].capabilities: []`). It is a scrape source with no drop-in alternative
behind a shared interface, like `observability/node-exporter`. node-exporter reports
disk I/O; this component reports the drive's own health counters, which node-exporter
does not read.

## Contents

A `kind: helm` wrapper over the `prometheus-smartctl-exporter` chart
(`https://prometheus-community.github.io/helm-charts`, version `0.17.1`, appVersion
`v0.14.0`), plus `manifests/00-namespace.yaml`. The rendered workload
(`grep '^kind:' rendered/manifest.yaml`) is:

- `DaemonSet` (`smartctl-exporter-0`). The chart appends the `-<idx>` suffix.
- `Service` (`smartctl-exporter`, ClusterIP, port `80` → the container's `http` port
  `9633`).
- `ServiceAccount` (`smartctl-exporter`, from `manifests/10-serviceaccount.yaml` with
  `automountServiceAccountToken: false`; the chart's own has no automount switch).
- A dedicated `smartctl-exporter` `Namespace` (the chart ships none).

No rendered object sets `metadata.namespace`. The workload lands in the
Application's destination namespace, which MUST be `smartctl-exporter`, the namespace
this artifact ships and labels.

The image is pinned by tag and digest:
`quay.io/prometheuscommunity/smartctl-exporter:v0.14.0@sha256:cfe22c36…`.

The render contains **no** CRD, `ServiceMonitor`, `PrometheusRule` or RBAC binding:

- **`rbac.create: false`.** The chart would bind the ServiceAccount to a
  PodSecurityPolicy ClusterRole that does not exist, because PSP was removed in
  Kubernetes 1.25.
- **ServiceMonitor and PrometheusRule are not shipped.** The chart's bundled rules
  cover the overall verdict, NVMe fields, interface speed and temperature. None reads
  an ATA raw counter, so a SATA disk that reports PASSED with pending sectors would
  stay silent.

## Host access and security posture (essential, intentional)

The chart hard-codes the container `securityContext` to `privileged: true` and
`runAsUser: 0`, and no value changes it. Both are required:

- **Root:** smartctl's ATA/SCSI/NVMe pass-through ioctls need root or `CAP_SYS_RAWIO`.
- **Privileged:** a non-privileged container gets the runtime's default device cgroup
  allowlist. Opening a host block device then fails whatever capabilities are granted.

The pod also mounts the host's `/dev` at `/hostdev` (`hostPath`). It is not
`hostNetwork`.

The `no_privileged_containers` policy allow-lists exactly this container
(`DaemonSet/smartctl-exporter-0`, container `main`, under the empty-namespace key
because the render carries no namespace; #885).

## Architecture

The upstream image is published for **`linux/amd64` only**: v0.14.0 is a manifest
list with a single entry. The catalog therefore sets
`nodeSelector: {kubernetes.io/os: linux, kubernetes.io/arch: amd64}`. A node of
another architecture gets no pod and so no disk health data; the consumer covers it
another way.

## Resources

- Requests: cpu `10m`, memory `32Mi`.
- Limits: memory `128Mi`.
- No CPU limit. A scrape blocks while smartctl runs, so throttling would stretch
  scrapes towards their timeout.

## Namespace & Pod Security

The component ships a dedicated `smartctl-exporter` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule, ADR-0032). It carries
`pod-security.kubernetes.io/enforce: privileged` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`privileged` is derived from the render. The pod has a privileged container and a
`hostPath` volume, both Baseline controls, so `baseline` and `restricted` would reject
it. It also runs as root, which only Restricted forbids. `task scan:psa-conformance`
checks the declared level against the render.

## Collection cost

Scrapes drive collection:

- A scrape re-runs smartctl for a device only when that device's cached result is
  older than `--smartctl.interval`. The chart default, kept here, is `120s`.
- A device rescan runs on its own timer.

SMART reads are non-queued commands on SATA drives, so each one holds the drive's
command queue while it runs. A consumer with latency-sensitive writers on SATA disks
(for example etcd) SHOULD raise the interval and roll the DaemonSet out to those nodes
last.

## Consumer obligations (out of scope here)

The consumer adds, in its Argo overlay:

- **Destination namespace `smartctl-exporter`.** The rendered workload carries no
  namespace of its own.
- **Scrape wiring:** a `ServiceMonitor`/`PodMonitor` or an Alloy scrape of the
  Service's `http` port, including the `scrapeTimeout` for one collection.
- **Network policy:** ingress to port `9633` from the scraper only. The pod needs no
  egress.
- **Alert rules.** Alert on the raw counters, not only the drive's own verdict:
  - ATA attributes 5, 197 and 198 (raw)
  - NVMe media errors, critical warning and spare below threshold
  - `smartctl_device_smartctl_exit_status` bits 0–2, which mean the device could not
    be read
- **Optional hardening and tuning:**
  - `readOnlyRootFilesystem: true`; the exporter writes nothing.
  - A longer `--smartctl.interval`.
  - Tolerations beyond the shipped `NoSchedule`/`Exists`; a `NoExecute`-tainted node
    evicts the pod.
- **Namespace overlay:** the `enforce-version` pin, the audit/warn modes and the PNI
  labels.
- The Argo `Application` CR itself, with its sync-wave annotation.

## Sync-wave

`0`, the catalog default. The component has no catalog-internal dependencies.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/smartctl-exporter:0.1.0
```

The registry tag is the bare SemVer (`task push` strips the leading `v`). The git tag
is `observability/smartctl-exporter-v0.1.0`.

## Related ADRs

- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0018 — Policy stack](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md) — the `no_privileged_containers` allow-list entry.
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0028 — Strict-B CRD management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — N/A; the render ships no CRDs.
- [ADR-0032 — Namespace / PSA ownership model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0032-catalog-namespace-psa-ownership.md)

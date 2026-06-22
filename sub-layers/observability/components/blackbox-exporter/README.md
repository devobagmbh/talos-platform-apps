# Component `observability/blackbox-exporter`

[blackbox_exporter](https://github.com/prometheus/blackbox_exporter) — a synthetic
prober that probes endpoints over **HTTP/HTTPS, TCP, and DNS** and exposes the
result on the Prometheus multi-target `/probe` endpoint. It does not store or alert;
it is a stateless exporter that the cluster's **Grafana Alloy** (`observability/alloy`)
scrapes with a per-target `module` + `target`. Published as an independently
versioned OCI artifact (ADR-0009).

This component provides **no swappable capability** (`compatibility.yaml`
`provides[].capabilities: []`). blackbox-exporter is the canonical provider of the
Prometheus multi-target probe interface — there is no drop-in alternative in this
catalog implementing the same interface, so it is an api-surface-only component
(precedent: `observability/kube-state-metrics`, `lifecycle/providers`).

## Role in the LGTM-A design

Per the target architecture (talos-platform-apps#183) and the monitoring design
(talos-platform-docs ADR-0015), blackbox-exporter is one of Alloy's scrape targets
and the engine of the **bidirectional cross-cluster watchdog**: each cluster
probes the *other* cluster's endpoints (Alertmanager / Mimir / Grafana) so a
whole-cluster failure is detected from the surviving side (the
"if a cluster dies, no one screams" gap), complemented by `absent()` rules on the
remote-written series.

## Contents

A `kind: helm` wrapper over the `prometheus-blackbox-exporter` chart
(`https://prometheus-community.github.io/helm-charts`, version `11.13.0`,
appVersion `v0.28.0`) plus `manifests/00-namespace.yaml`:

- `Deployment` (`blackbox-exporter`) + `Service` (`:9115`) + `ServiceAccount`
  (`automountServiceAccountToken: false` — `/probe` needs no API access) + a
  `ConfigMap` holding the probe **modules**.
- A dedicated `blackbox-exporter` `Namespace` (the chart ships none),
  `pod-security.kubernetes.io/enforce: restricted`.

### Probe modules shipped (cluster-agnostic defaults)

`http_2xx`, `https_2xx` (TLS verify off — probes reachability behind the per-cluster
self-signed wildcard cert, not the trust chain), `tcp_connect`, `dns_udp`. **No
`icmp` module**: icmp needs `CAP_NET_RAW`, which `enforce: restricted` forbids.
Endpoint health is fully covered by HTTP/TCP probes; icmp would be a deliberate,
documented overlay change (add `NET_RAW` + relax PSA) — out of scope for the catalog.

The pinned securityContext — **pod-level** `runAsNonRoot` + `seccompProfile:
RuntimeDefault`, **container-level** runAsNonRoot 65534 + drop ALL caps +
`readOnlyRootFilesystem` + `allowPrivilegeEscalation: false` + `seccompProfile:
RuntimeDefault` — is explicit-not-inherited so a future chart bump cannot silently
weaken the posture. The chart ships **no** `seccompProfile` at either level, which
`enforce: restricted` requires, so it is set here (verified present in
`rendered/manifest.yaml`, not just declared).

## Consumer obligations

- **Probe targets are NOT in this artifact.** Which endpoints a cluster probes —
  and the bidirectional cross-cluster targets — are cluster-specific and live in the
  consumer's Prometheus `Probe` CRs / Alloy scrape config (a monitoring-config
  concern, not an ADR-0024 freeze-line shape). `customization.yaml` is therefore an
  empty freeze-line.
- **Custom modules**, if ever needed beyond the shipped four, are a future Shape (b)
  config override — the catalog ships usable defaults, so none is required.
- The consumer adds the PNI labels + `pod-security.kubernetes.io/enforce-version`
  pin + audit/warn modes in its Argo overlay (ADR-0032); the catalog ships only the
  `enforce` level + ownership labels.

## OCI

`oci://ghcr.io/devobagmbh/talos-platform-apps/observability/blackbox-exporter:<X.Y.Z>`
(git tag `observability/blackbox-exporter-vX.Y.Z`). Sync-wave **0** (a scrape target,
like `kube-state-metrics` / `node-exporter`).

## Related

- [talos-platform-apps#183](https://github.com/devobagmbh/talos-platform-apps/issues/183) — LGTM-A target architecture
- [talos-platform-apps#38](https://github.com/devobagmbh/talos-platform-apps/issues/38) — observability epic
- [ADR-0015](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md) — monitoring architecture (bidirectional probes)
- [ADR-0009](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md) · [ADR-0024](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md) · [ADR-0032](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0032-namespace-psa-ownership.md)

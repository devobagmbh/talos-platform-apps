# Component `observability/alloy`

[Grafana Alloy](https://grafana.com/docs/alloy/latest/) — the unified telemetry
collector (OSS, Apache 2.0; successor to the Grafana Agent). Deployed as a
node-local **DaemonSet**, Alloy replaces Promtail as the platform log collector and
additionally scrapes Prometheus-format metrics and receives OTLP traces, forwarding
each to its respective sink (Loki for logs, Mimir for metrics, Tempo for traces).

It implements **three** capabilities in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Log collection | `logs-collect` | `label-move` |
| Prometheus-format metrics scrape | `metrics-scrape` | `drop-in` |
| Trace collection (OTLP) | `traces-collect` | `label-move` |

A consumer can substitute another implementation of any of these (e.g. fluent-bit
for logs, otelcol for traces) per the index `swap_class`.

## Contents

A `kind: helm` wrapper over the `alloy` chart
(`https://grafana.github.io/helm-charts`, version `1.10.0`, appVersion `v1.17.0`)
plus `manifests/00-namespace.yaml`:

- A `DaemonSet` (`alloy`) — one Alloy pod per node — with the chart's
  config-reloader sidecar, plus `Service`, `ServiceAccount`, and the read
  `ClusterRole`/`ClusterRoleBinding` the discovery/log/metrics components need.
- A dedicated `alloy` `Namespace` carrying `pod-security.kubernetes.io/enforce:
  restricted`.

The Alloy image is pinned to the chart's appVersion
(`docker.io/grafana/alloy:v1.17.0`); the config-reloader image is pinned to a
SHA256 digest by the chart — never `:latest`.

The chart's `crds` subchart (`crds.create`) is disabled: this component ships **no**
CustomResourceDefinitions, so strict-B (ADR-0028) does not apply and there is no
`-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Freeze-line (ADR-0024 v2, Shape b)

Alloy is **not** cluster-agnostic: its pipeline — the sources and the three sink
endpoints (Loki/Mimir/Tempo) — is cluster-specific and differs per consumer. The
freeze-line therefore splits ownership as Shape (b): the **workload** (the rendered
DaemonSet) is catalog-owned and signed; the **config** is 100% consumer-owned.

The workload mounts an EXISTING consumer-supplied ConfigMap `alloy-config` (key
`config.alloy`) at `/etc/alloy` and runs `/etc/alloy/config.alloy`
(`alloy.configMap.create: false`). The consumer owns the whole `config.alloy` file;
the signed workload is never patched.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships
none of these:

- **`alloy-config` ConfigMap** with a `config.alloy` key carrying the full Alloy
  pipeline: the sources (e.g. `discovery.kubernetes` + `loki.source.kubernetes` for
  pod logs, `otelcol.receiver.otlp` for traces/metrics ingest) and the **three sink
  endpoints** — the Loki push URL, the Mimir remote-write URL, and the Tempo OTLP
  export URL. These URLs are cluster-specific and live nowhere in the catalog.
- **Shape (b) vs (c) for authenticated sinks.** For the default same-cluster
  full-stack consumer the sink endpoints need no auth → a plain `alloy-config`
  ConfigMap (Shape b) is correct. **If** a consumer forwards to **cross-cluster**
  sinks needing bearer/basic-auth credentials, the credential portion is the
  consumer's **Shape (c)** Secret concern (dex precedent): credentials MUST NOT be
  shipped in a plain ConfigMap. The consumer authors the `config.alloy` to read the
  credential from a mounted/`env`-referenced Secret rather than inlining it.
- **Node scheduling** — `tolerations` / `nodeSelector` to schedule Alloy on tainted
  nodes (e.g. control-plane) belong in the consumer Helm values overlay; the catalog
  leaves them at the chart defaults.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors and the pod
  `platform.io/capability-provider.*` labels, plus the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor)
  and the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

## Namespace & Pod Security

The component ships a dedicated `alloy` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule) carrying
`pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the posture the **default** workload provably satisfies — confirmed
against the rendered DaemonSet pod template: the pod sets `runAsNonRoot: true` +
`seccompProfile: RuntimeDefault`, and **both** containers (`alloy` and
`config-reloader`) set `allowPrivilegeEscalation: false` + `capabilities.drop:
[ALL]` (+ `readOnlyRootFilesystem`, `runAsNonRoot`, `runAsUser: 473`). The default
workload ships **no** host mounts (`mounts.varlog` / `mounts.dockercontainers`,
`hostNetwork`, `hostPID` all `false`): it collects pod logs through the Kubernetes
API (`loki.source.kubernetes`) + the chart RBAC and receives OTLP over the network,
neither of which needs host access.

> A consumer that needs **journald** or **direct `/var/log`** collection must enable
> hostPath mounts and accept a more permissive PSA level (`baseline`/`privileged`).
> That is a deliberate consumer override / future component variant, not the default
> frozen workload shipped here.

## Sync-wave

`20` — Alloy forwards to the three sink storage components (Loki/Mimir/Tempo, wave
10), so it deploys after them. On a forwarder-only consumer it is configured (via
its `config.alloy`) as a pure forwarder to the full-stack consumer's endpoints.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/alloy:0.1.0
```

OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is `observability/alloy-v0.1.0` (kept
distinct — registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

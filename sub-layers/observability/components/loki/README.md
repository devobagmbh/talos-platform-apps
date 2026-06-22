# Component `observability/loki`

[Grafana Loki](https://grafana.com/docs/loki/latest/) — the platform **log store**
and **LogQL query endpoint** (OSS, AGPL-3.0). Deployed in **SingleBinary** mode (one
`StatefulSet`, one replica, every Loki target in a single process) backed by **S3
(Garage)** for both the log chunks and the ruler.

It implements **two** capabilities in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Log storage | `logs-storage` | `data-migration` |
| Log query endpoint (LogQL) | `logs-query` | `drop-in` |

A consumer can substitute another implementation (e.g. `victoria-logs`) per the index
`swap_class` — swapping the *store* is a `data-migration` (the chunks must be
migrated), swapping the *query endpoint* is `drop-in` (LogQL-compatible).

## Why SingleBinary

The catalog consumers are small single-node clusters. Loki's distributed /
`SimpleScalable` topologies (separate read/write/backend deployments, memcached
caches, an nginx gateway) are massively over-provisioned for that scale. SingleBinary
runs the entire Loki read+write+backend path in one container, scales the
`SimpleScalable` components to `replicas: 0`, and serves the read and write APIs
directly (no gateway). The result is a single `StatefulSet` pod plus its `Service`s,
`ServiceAccount`, and the chart's read-only `ClusterRole`/`ClusterRoleBinding`.

## Contents

A `kind: helm` wrapper over the `loki` chart
(`https://grafana.github.io/helm-charts`, version `6.55.0`, appVersion `3.6.7`) plus
`manifests/00-namespace.yaml`:

- A `StatefulSet` (`loki`, `singleBinary.replicas: 1`) running
  `docker.io/grafana/loki:3.6.7` — the image is pinned to the chart appVersion, never
  `:latest`.
- `Service`s (the Loki HTTP/gRPC endpoints + the memberlist headless service), a
  `ServiceAccount`, and the chart's read-only `ClusterRole`/`ClusterRoleBinding`.
- The chart-generated `loki` config `ConfigMap` and the `loki-runtime` `ConfigMap`
  (the chart's runtime-overrides file — distinct from the consumer's
  `loki-runtime-config`, see below).
- A dedicated `loki` `Namespace` carrying `pod-security.kubernetes.io/enforce:
  restricted`.

Disabled (not needed for a single-node SingleBinary store): `gateway` (SingleBinary
serves directly), `chunksCache`/`resultsCache` (memcached), `lokiCanary`, the helm
`test` hook, the rule-watching `sidecar.rules` (the ruler reads its rules from the S3
ruler bucket), and the bundled `monitoring`/`selfMonitoring` (Alloy scrapes Loki's
metrics endpoint externally — `observability/alloy`).

The chart ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does not
apply and there is no `-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Freeze-line (ADR-0024 v2, Shapes a + c)

Loki is **not** cluster-agnostic: its **S3 connection** (endpoint, region, bucket
names, credentials) is per-cluster and 100% consumer-owned. The freeze-line keeps that
connection out of the frozen workload:

- The **workload** (the rendered `StatefulSet` + `Service`s + RBAC + the loki config
  `ConfigMap` + the `Namespace`) is catalog-owned and signed — never consumer-patched.
- The rendered Loki config references `${VAR}` **placeholders**, not real
  endpoints/keys. Loki resolves them at runtime from consumer-supplied env via the
  `-config.expand-env=true` flag (set on the SingleBinary container args; the
  consumer-owned env is wired onto the container's `envFrom`).

Two consumer-supplied refs feed the placeholders:

- **Shape (a)** — `ConfigMap` `loki-runtime-config` (non-secret), `envFrom`:
  `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_CHUNKS`, `S3_BUCKET_RULER`.
- **Shape (c)** — `Secret` `loki-runtime-secret`, `envFrom`: `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.

These map into `common.storage.s3` (chunks) and `ruler_storage.s3` (ruler) in the
rendered config. See `customization.yaml`.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none
of these:

- **`loki-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` (the explicit Garage S3
  endpoint URL, e.g. `https://garage.<cluster>:3900`), `S3_REGION` (typically
  `garage`), `S3_BUCKET_CHUNKS`, `S3_BUCKET_RULER`.
- **`loki-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY` (the Garage S3 credentials).
- **The two Garage buckets** — a chunks bucket and a ruler bucket, provisioned against
  the cluster's Garage (`storage-objects/garage`); their names are what
  `S3_BUCKET_CHUNKS` / `S3_BUCKET_RULER` point at.
- **Persistent storage** — the SingleBinary `StatefulSet`'s `storage` volume claim
  binds to the cluster's default StorageClass; tune `singleBinary.persistence` in the
  consumer overlay if a specific class/size is needed.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor),
  and the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

The Garage specifics are baked into the workload (not consumer-tunable): path-style
addressing (`s3forcepathstyle: true`), TLS on (`insecure: false`). Only the connection
*values* are consumer-supplied.

## Namespace & Pod Security

The component ships a dedicated `loki` `Namespace` (`manifests/00-namespace.yaml`,
sole-claimant rule) carrying `pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the posture the workload provably satisfies — confirmed against the
rendered SingleBinary pod template:

- **Pod**: `runAsNonRoot: true` + `seccompProfile: RuntimeDefault`. The chart's pod
  default omits `seccompProfile` (which would force a `baseline` floor), so the helm
  values add it explicitly.
- **Container** (`loki`): `allowPrivilegeEscalation: false` + `capabilities.drop:
  [ALL]` + `seccompProfile: RuntimeDefault` (+ `readOnlyRootFilesystem`,
  `runAsNonRoot`, `runAsUser: 10001`).

With the rule sidecar disabled, the pod is a single container, so the restricted
container predicates hold for every container in the pod.

## Sync-wave

`10` — Loki needs the cluster's Garage S3 endpoint + the chunks/ruler buckets, which
the foundational `storage-objects/garage` (sync-wave 0) provides. The log collector
`observability/alloy` (sync-wave 20) forwards to Loki, so it comes after.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/loki:0.1.0
```

The OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is `observability/loki-v0.1.0` (kept distinct —
registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0007 — Platform object store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

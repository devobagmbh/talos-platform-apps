# Component `observability/loki`

[Grafana Loki](https://grafana.com/docs/loki/latest/) — the platform **log store**
and **LogQL query endpoint** (OSS, AGPL-3.0). Deployed in **SingleBinary** mode (one
`StatefulSet`, one replica, every Loki target in a single process) backed by an
**S3-compatible object store** (the `s3-object` capability) for both the log chunks and
the ruler.

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
`ServiceAccount`, and the chart's zero-permission `ClusterRole`/`ClusterRoleBinding`
(`rules: []` — no API access granted).

## Contents

A `kind: helm` wrapper over the `loki` chart
(`https://grafana.github.io/helm-charts`, version `6.55.0`, appVersion `3.6.7`) plus
`manifests/00-namespace.yaml`:

- A `StatefulSet` (`loki`, `singleBinary.replicas: 1`) running
  `docker.io/grafana/loki:3.6.7` — the image is pinned to the chart appVersion, never
  `:latest`.
- `Service`s (the Loki HTTP/gRPC endpoints + the memberlist headless service), a
  `ServiceAccount`, and the chart's zero-permission `ClusterRole`/`ClusterRoleBinding`
  (`rules: []` — no API access granted).
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
  `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_CHUNKS`, `S3_BUCKET_RULER`, `S3_INSECURE`.
- **Shape (c)** — `Secret` `loki-runtime-secret`, `envFrom`: `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.

These map into `common.storage.s3` (chunks) and `ruler_storage.s3` (ruler) in the
rendered config. See `customization.yaml`.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none
of these:

- **`loki-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` (the explicit S3
  endpoint URL, e.g. `https://garage.<cluster>:3900`), `S3_REGION` (S3 region; the
  Garage impl uses `garage`), `S3_BUCKET_CHUNKS`, `S3_BUCKET_RULER`, and `S3_INSECURE` —
  the S3 endpoint TLS mode, a required key set to the lowercase string `"false"`
  (TLS/HTTPS to the S3 endpoint — the secure choice) or `"true"` (plain HTTP, for a
  TLS-less S3 endpoint, e.g. an internal NAS).
- **`loki-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY` (the S3 credentials).
- **The required buckets** — a chunks bucket and a ruler bucket — must exist in the
  `s3-object` backend before the workload runs; their names are what `S3_BUCKET_CHUNKS` /
  `S3_BUCKET_RULER` point at. The platform's active impl (Garage) provisions them via
  `storage-objects/garage-buckets` (sync-wave 10), not the `garage` workload (wave 0).
  NOTE: the chunks and ruler buckets MUST exist before Loki can write — Loki CrashLoops
  on a missing S3 bucket until it appears (a visible, self-healing failure). Since
  `garage-buckets` and `loki` share sync-wave 10, the consumer MUST ensure bucket
  readiness, e.g. by ordering `garage-buckets` ahead of `loki` in its composition.
- **Persistent storage** — the SingleBinary `StatefulSet`'s `storage` volume claim
  binds to the cluster's default StorageClass; tune `singleBinary.persistence` in the
  consumer overlay if a specific class/size is needed. NOTE (DR): committed chunks live
  in the S3 object store and survive pod/node loss; the PVC holds only the ingester WAL + TSDB
  index cache (recent, not-yet-compacted data) and uses
  `persistentVolumeClaimRetentionPolicy: whenDeleted: Delete`, so deleting the
  `StatefulSet` (Argo prune / re-install) loses the recent pre-compaction window. For
  planned maintenance, flush before deletion.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor),
  and the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

Path-style addressing (`s3forcepathstyle: true`) is baked into the workload (the
self-hosted / path-style S3 standard — MinIO, Garage and similar require it) and is not
consumer-tunable. The S3 endpoint TLS mode is consumer-owned via `S3_INSECURE`
(`insecure: ${S3_INSECURE}`), a required key: `"false"` keeps TLS on (the secure
choice), `"true"` selects plain HTTP for a TLS-less S3 endpoint. The connection *values*
are consumer-supplied.

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

`10` — Loki needs the cluster's S3 endpoint + the chunks/ruler buckets (s3-object
capability; the platform's Garage impl provides them at sync-wave 0/10). The log
collector `observability/alloy` (sync-wave 20) forwards to Loki, so it comes after.

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

# Component `observability/mimir`

[Grafana Mimir](https://grafana.com/docs/mimir/latest/) — the platform **metrics
store** and **PromQL query endpoint** (OSS, AGPL-3.0). Deployed in the **classic
microservices architecture** (the `mimir-distributed` chart 5.x, no Kafka), every core
component at one replica, backed by **S3 (Garage)** for both the TSDB blocks and the
ruler. Mimir is the long-term metrics analogue of `observability/loki` (logs).

It implements **two** capabilities in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Metrics storage (time-series store) | `metrics-storage` | `data-migration` |
| Metrics query endpoint (PromQL) | `metrics-query` | `drop-in` |

A consumer can substitute another implementation (e.g. `victoria-metrics`, `thanos`)
per the index `swap_class` — swapping the *store* is a `data-migration` (the blocks
must be migrated), swapping the *query endpoint* is `drop-in` (PromQL-compatible).

## Why classic 5.8.0, not 6.x / Kafka

The catalog consumers are small single-workload clusters. Chart **6.x** (latest,
`6.0.6` / appVersion `3.0.4`) defaults to the Kafka-based **ingest-storage
architecture** (`kafka.enabled: true`, `ingest_storage.enabled: true`) — it mandates a
Kafka broker, which directly violates the small-single-node-footprint mandate. Chart
**5.8.0** is the latest release of the **classic microservices architecture** (no
Kafka), the correct footprint. This is a deliberate not-latest pin.

The footprint is the smallest sensible for a small cluster: every Mimir core
microservice runs at `replicas: 1` (distributor, ingester, querier, query-frontend,
query-scheduler, store-gateway, compactor, ruler). These microservices are inherent to
`mimir-distributed`; the chart does not offer a single-process monolith, so one replica
each is the right granularity (zone-aware replication off, replication factor 1).

## Contents

A `kind: helm` wrapper over the `mimir-distributed` chart
(`https://grafana.github.io/helm-charts`, version `5.8.0`, appVersion `2.17.0`) plus
`manifests/00-namespace.yaml`:

- Eight workloads running `grafana/mimir:2.17.0` (pinned to the chart appVersion, never
  `:latest`): `Deployment`s `mimir-distributor`, `mimir-querier`,
  `mimir-query-frontend`, `mimir-query-scheduler`, `mimir-ruler`; `StatefulSet`s
  `mimir-ingester`, `mimir-store-gateway`, `mimir-compactor`.
- The `Service`s (per-component HTTP/gRPC + memberlist), `ServiceAccount`s, and the
  chart RBAC.
- The chart-generated `mimir-config` `ConfigMap` (the Mimir runtime config) and the
  `mimir-runtime` `ConfigMap` (the chart's runtime-overrides file — distinct from the
  consumer's `mimir-runtime-config`, see below).
- A dedicated `mimir` `Namespace` carrying `pod-security.kubernetes.io/enforce:
  restricted`.

Disabled (not needed for the small single-node footprint): `minio` (external Garage S3
instead), `nginx`/`gateway` (a consumer fronts Mimir via its own gateway),
`alertmanager` (the platform ships a standalone alertmanager component, so no
alertmanager S3 bucket is needed here), `overrides_exporter`, `rollout_operator` (only
needed for zone-aware HA StatefulSet rollouts — we run replicas 1 with no zone
awareness), all memcached caches (`chunks-cache`, `index-cache`, `metadata-cache`,
`results-cache`), and the bundled metamonitoring (`metaMonitoring.serviceMonitor`,
`metaMonitoring.grafanaAgent`) plus the smoke-test pod — Alloy scrapes Mimir's metrics
endpoint externally (`observability/alloy`).

The `ruler` is **kept** (`ruler.enabled: true`): it evaluates recording/alerting rules
and reads them from the ruler S3 bucket.

The chart ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does not apply
and there is no `-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Freeze-line (ADR-0024 v2, Shapes a + c)

Mimir is **not** cluster-agnostic: its **S3 connection** (endpoint, region, bucket
names, credentials) is per-cluster and 100% consumer-owned. The freeze-line keeps that
connection out of the frozen workload:

- The **workload** (the rendered Deployments/StatefulSets + `Service`s + RBAC + the
  `mimir-config` `ConfigMap` + the `Namespace`) is catalog-owned and signed — never
  consumer-patched.
- The rendered Mimir config references `${VAR}` **placeholders**, not real
  endpoints/keys. Mimir resolves them at runtime via the `-config.expand-env=true`
  flag, which is already in every component container's default args in this chart (no
  `extraArgs` override needed). The consumer-owned env is wired onto every component
  pod's `envFrom` via the chart's top-level `global.extraEnvFrom` knob.

Two consumer-supplied refs feed the placeholders:

- **Shape (a)** — `ConfigMap` `mimir-runtime-config` (non-secret), `envFrom`:
  `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_BLOCKS`, `S3_BUCKET_RULER`, `S3_INSECURE`,
  `RULER_ALERTMANAGER_URL`.
- **Shape (c)** — `Secret` `mimir-runtime-secret`, `envFrom`: `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.

These map into `common.storage.s3` (credentials/endpoint/region),
`blocks_storage.s3.bucket_name` (blocks), `ruler_storage.s3.bucket_name` (ruler), and
`ruler.alertmanager_url` (`RULER_ALERTMANAGER_URL`) in the rendered config. See
`customization.yaml`.

**`RULER_ALERTMANAGER_URL`** — the built-in alertmanager is disabled (the platform uses a
standalone one), so the ruler must be pointed at the consumer's Alertmanager (e.g.
`http://alertmanager-operated.monitoring.svc:9093`). Unset → empty → the ruler evaluates
rules but does not notify (safe default).

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none
of these:

- **`mimir-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` (the explicit Garage S3
  endpoint URL, e.g. `https://garage.<cluster>:3900`), `S3_REGION` (typically
  `garage`), `S3_BUCKET_BLOCKS`, `S3_BUCKET_RULER`, and `S3_INSECURE` — the S3 endpoint
  TLS mode: `"false"` = TLS/HTTPS to the S3 endpoint (default, secure); `"true"` = plain
  HTTP, for a TLS-less Garage (e.g. an internal NAS Garage).
- **`mimir-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY` (the Garage S3 credentials).
- **The two Garage buckets** — a blocks bucket and a ruler bucket, provisioned by
  `storage-objects/garage-buckets` (sync-wave 10), not the `garage` workload (wave 0);
  their names are what `S3_BUCKET_BLOCKS` / `S3_BUCKET_RULER` point at. NOTE: the
  buckets MUST exist before Mimir can write — the ingester/compactor/store-gateway
  CrashLoop on a missing S3 bucket until it appears (a visible, self-healing failure).
  Since `garage-buckets` and `mimir` share sync-wave 10, the consumer SHOULD ensure
  bucket readiness, e.g. by ordering `garage-buckets` ahead of `mimir` in its
  composition.
- **Persistent storage** — the ingester / store-gateway / compactor `StatefulSet`s bind
  their data volume claims to the cluster's default StorageClass; tune the chart
  `persistence` values in the consumer overlay if a specific class/size is needed. NOTE
  (DR): committed blocks live in S3 (Garage) and survive pod/node loss; the PVCs hold
  the ingester WAL + the store-gateway/compactor working set (recent, not-yet-flushed
  data), so deleting a `StatefulSet` (Argo prune / re-install) loses the recent
  pre-flush window. For planned maintenance, flush before deletion. Recovery: on
  restart the ingester replays that WAL in memory before it goes Ready — at the
  4Gi / 600k-series profile (see the ingester `resources` block) this replay is the
  peak-memory, slowest-recovery moment; a larger cardinality ceiling widens the window.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor),
  and the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

Path-style addressing is baked into the workload (forced via `bucket_lookup_type: path`
— Garage requires it) and is not consumer-tunable. The S3 endpoint TLS mode is
consumer-owned via `S3_INSECURE` (`insecure: ${S3_INSECURE}`): unset or `"false"` keeps
TLS on (the secure default), `"true"` selects plain HTTP for a TLS-less Garage. The
connection *values* are consumer-supplied.

## Namespace & Pod Security

The component ships a dedicated `mimir` `Namespace` (`manifests/00-namespace.yaml`,
sole-claimant rule) carrying `pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the posture every workload provably satisfies — confirmed against all
eight rendered pod templates (15 workload containers total, no initContainers, no
`hostNetwork`/`hostPID`):

- **Pod** (all 8): `runAsNonRoot: true` + `seccompProfile: RuntimeDefault` (+
  `runAsUser`/`runAsGroup`/`fsGroup` 10001).
- **Container** (all 15): `allowPrivilegeEscalation: false` + `capabilities.drop:
  [ALL]` (+ `readOnlyRootFilesystem`).

Unlike the `loki` chart (which omits the pod `seccompProfile` and needs a values
override), `mimir-distributed` sets a fully `restricted`-compliant `securityContext` out
of the box, so the helm values add **no** `securityContext` overrides. The level holds
cluster-wide for every pod kind the chart renders.

## Sync-wave

`10` — Mimir needs the cluster's Garage S3 endpoint + the blocks/ruler buckets, which
the foundational `storage-objects/garage` (sync-wave 0) provides. The metrics collector
`observability/alloy` (sync-wave 20) forwards to Mimir, so it comes after.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/mimir:0.1.0
```

The OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is `observability/mimir-v0.1.0` (kept distinct —
registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0007 — Platform object store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

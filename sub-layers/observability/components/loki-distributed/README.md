# Component `observability/loki-distributed`

[Grafana Loki](https://grafana.com/docs/loki/latest/) — the platform **log store** and
**LogQL query endpoint** (OSS, AGPL-3.0), deployed in the chart's **`Distributed`**
deployment mode: every Loki target runs as its own workload, backed by an
**S3-compatible object store** (the `s3-object` capability) for both the log chunks and
the ruler.

It implements **two** capabilities in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Log storage | `logs-storage` | `data-migration` |
| Log query endpoint (LogQL) | `logs-query` | `drop-in` |

## Relationship to `observability/loki`

`observability/loki` ships the **same chart at the same version** in `SingleBinary`
mode — one `StatefulSet`, one replica — for single-node consumers. This component is the
**second, independently versioned** artifact: a multi-node consumer selects highly
available log storage by pointing its Argo `Application` at `observability/loki-distributed`
**instead of** `observability/loki`. The two are alternative topologies of one store,
never deployed together; each ships its own dedicated namespace so an overlapping
migration window cannot make two Argo `Application`s contend over the same objects.

Consumer-visible contract parity is deliberate: the required env/secret **key names** are
byte-identical across both components, so a consumer that already supplies the
SingleBinary component's S3 keys reuses the same values here — only the ConfigMap/Secret
**names** are component-scoped (see § Freeze-line).

## Contents

A `kind: helm` wrapper over the `loki` chart
(`https://grafana.github.io/helm-charts`, version `6.55.0`, appVersion `3.6.7`) plus
`manifests/00-namespace.yaml`. Every workload runs
`docker.io/grafana/loki:3.6.7` — pinned to the chart appVersion, never `:latest`.

| Workload | Kind | Replicas | Path |
|---|---|---|---|
| `loki-distributed-distributor` | `Deployment` | 2 | ingest |
| `loki-distributed-ingester` | `StatefulSet` | 3 | ingest |
| `loki-distributed-querier` | `Deployment` | 2 | query |
| `loki-distributed-query-frontend` | `Deployment` | 2 | query |
| `loki-distributed-query-scheduler` | `Deployment` | 2 | query |
| `loki-distributed-index-gateway` | `StatefulSet` | 2 | query |
| `loki-distributed-ruler` | `StatefulSet` | 2 | rule evaluation |
| `loki-distributed-compactor` | `StatefulSet` | 1 | background maintenance |

Alongside them: 13 `Service`s, a `PodDisruptionBudget` (`maxUnavailable: 1`) per
multi-replica component, a `ServiceAccount`, the chart's zero-permission
`ClusterRole`/`ClusterRoleBinding` (`rules: []` — no API access granted), the
chart-generated `loki` config `ConfigMap` and the `loki-runtime` overrides `ConfigMap`,
and the dedicated `loki-distributed` `Namespace`.

The `Service` shapes are not uniform, so do not assume a `-headless` sibling exists for
every component. As rendered:

- **Load-balancing `ClusterIP` plus a `-headless` sibling** — `distributor`,
  `query-frontend`, `ingester`, `index-gateway` (these four are the only `-headless`
  Services in the artifact).
- **A single load-balancing `ClusterIP`** — `querier`, `compactor`.
- **A single headless `Service`** (`clusterIP: None`, no `-headless` name suffix) —
  `query-scheduler`, `ruler`.
- Plus the headless `loki-distributed-memberlist` gossip `Service`.

One consequence worth knowing before reading the render as broken: the compactor
`StatefulSet` names `loki-distributed-compactor-headless` in `spec.serviceName`, but no
`Service` of that name is emitted. That is upstream chart shape with no functional
consequence here — Kubernetes does not require the governing `Service` to exist, and the
single compactor is reached over its `ClusterIP` `Service`, which is what
`common.compactor_grpc_address` in the rendered config resolves. The other three
`StatefulSet`s resolve their `spec.serviceName` to a real headless `Service`.

The chart ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does not apply
and there is no `-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Why this topology

The design target is the **minimum** footprint under which the ingest and query paths
both survive the loss of any single pod.

- **Ingesters: 3, with `replication_factor: 3`.** Every log stream is written to all
  three ingesters, so the write quorum (2) still holds when one is lost.
- **Every workload spreads across nodes, not just the ingester.** All eight rendered
  workloads carry the chart's hard pod anti-affinity —
  `requiredDuringSchedulingIgnoredDuringExecution`, `topologyKey:
  kubernetes.io/hostname`, scoped per `app.kubernetes.io/component`. Each component's
  own replicas therefore land on distinct nodes (different components may still share
  one), so a node loss costs at most one replica of any given component. That is what
  makes pod-loss survival a node-loss survival too — and it is why this component
  targets a cluster with at least three schedulable nodes (see § Consumer obligations).
- **Zone-aware ingester replication is deliberately OFF** (the chart default is on).
  With it on, the chart renders three per-zone `StatefulSet`s labelled
  `rollout-group: ingester` and annotated `rollout-max-unavailable`, which are the
  coordination surface of the `rollout-operator` subchart the chart defaults to
  disabled. Rendering this component once with zone-awareness enabled confirmed the
  per-zone `StatefulSet`s use `updateStrategy: RollingUpdate` (not `OnDelete`), so the
  hazard is not a stalled rollout but an **uncoordinated** one: three independent
  `StatefulSet`s roll concurrently and can restart the holders of every replica of a
  stream at once. One flat `StatefulSet` of 3 is rolled a pod at a time by the
  `StatefulSet` controller itself. The upstream chart additionally recommends running
  Loki inside a single availability zone.
- **Stateless and query components: 2 each** (distributor, querier, query-frontend,
  query-scheduler, index-gateway). Two replicas is the smallest count under which
  losing one still leaves the path serving. The index-gateway is included because the
  queriers resolve the TSDB index through it — a single replica would be a read-path
  single point of failure.
- **Compactor: 1 — and this does not violate the single-pod-loss requirement.** The
  Loki compactor is a singleton by design: it owns index compaction plus retention and
  deletion for the whole cluster, and a second instance would contend over the same
  index objects. It sits on **neither** the ingest nor the query path, so while it is
  being rescheduled, writes and queries continue and only compaction/retention pauses.
- **Ruler: enabled, 2 replicas.** The SingleBinary sibling runs `-target=all`, which
  includes the ruler, so an enabled ruler is functional parity — and it is what makes
  the `S3_BUCKET_RULER` key meaningful. The chart's rule-watching `sidecar.rules`
  k8s-sidecar is disabled: this ruler reads its rules from the S3 ruler bucket, so the
  in-cluster watcher is redundant and would add a second container plus another image.
- **Not deployed** (left at the chart-default `replicas: 0`): the bloom
  gateway/planner/builder (an experimental accelerated-filtering path with its own
  object-storage layout), the pattern ingester, and the overrides-exporter (per-tenant
  limit metrics, meaningless in a single-tenant store). Enabling any of them is a
  deliberate catalog change with its own sizing and storage review.
- **Disabled**: the nginx `gateway` (see § Consumer entry points), the memcached
  `chunksCache`/`resultsCache`, the `lokiCanary` DaemonSet, the helm `test` hook, the
  chart's whole `monitoring` block — which covers **both** its `serviceMonitor`/`rules`
  scrape resources **and** its bundled dashboards — plus `selfMonitoring`, the bundled
  `minio`, and the `rollout_operator`. Scrape wiring and dashboards are consequently
  consumer-owned; § Consumer obligations states that split.

Each workload declares `requests.cpu` + `requests.memory` + `limits.memory` and no CPU
limit (a CPU limit only throttles; memory is the incompressible OOM risk). The values
are a platform starting point for a modest multi-node cluster; a consumer raises them
per-cluster through its Argo Kustomize overlay, not through a catalog PR.

## Consumer entry points

The chart's nginx gateway is **not** shipped (it would add an unpinned third-party image
and a second ingress surface to the signed artifact), so a consumer targets the
component's own `Service`s directly, both on port `3100`:

| Path | `Service` |
|---|---|
| Write (log push, e.g. from a collector) | `loki-distributed-distributor` |
| Read (LogQL, e.g. a Grafana datasource) | `loki-distributed-query-frontend` |

Both are regular `ClusterIP` `Service`s that load-balance across their replicas; the
`-headless` siblings exist for the components' internal gRPC discovery and are not the
consumer-facing entry points.

## Freeze-line (ADR-0024 v2, Shapes a + c)

Loki is **not** cluster-agnostic: its **S3 connection** (endpoint, region, bucket names,
credentials) is per-cluster and 100% consumer-owned. The freeze-line keeps that
connection out of the frozen workload:

- The **workload** (the rendered Deployments/StatefulSets + `Service`s + PDBs + RBAC +
  the loki config `ConfigMap` + the `Namespace`) is catalog-owned and signed.
- The rendered Loki config references `${VAR}` **placeholders**, not real
  endpoints/keys. Loki resolves them at runtime from consumer-supplied env via
  `-config.expand-env=true`, which the chart's `global.extraArgs` puts on **every**
  component container; the consumer-owned env is wired onto every container's `envFrom`
  via `global.extraEnvFrom`.

Two consumer-supplied refs feed the placeholders:

- **Shape (a)** — `ConfigMap` `loki-distributed-runtime-config` (non-secret), `envFrom`:
  `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_CHUNKS`, `S3_BUCKET_RULER`, `S3_INSECURE`.
- **Shape (c)** — `Secret` `loki-distributed-runtime-secret`, `envFrom`:
  `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`.

These map into `common.storage.s3` (chunks) and `ruler.storage.s3` (rules) in the
rendered config. See `customization.yaml`.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none
of these:

- **`loki-distributed-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` (the
  explicit S3 endpoint URL), `S3_REGION`, `S3_BUCKET_CHUNKS`, `S3_BUCKET_RULER`, and
  `S3_INSECURE` — the S3 endpoint TLS mode, a required key set to the lowercase string
  `"false"` (TLS/HTTPS — the secure choice) or `"true"` (plain HTTP, for a TLS-less S3
  endpoint).
- **`loki-distributed-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.
- **The required buckets** — a chunks bucket and a ruler bucket — MUST exist in the
  `s3-object` backend before the workload runs; their names are what `S3_BUCKET_CHUNKS`
  / `S3_BUCKET_RULER` point at. Loki CrashLoops on a missing S3 bucket until it appears
  (a visible, self-healing failure), so the consumer MUST order bucket provisioning
  ahead of this component in its composition.
- **At least three schedulable nodes.** *Every* workload in this artifact — not only the
  ingester — carries the chart's hard `requiredDuringSchedulingIgnoredDuringExecution`
  pod anti-affinity on `topologyKey: kubernetes.io/hostname`, scoped to its own
  `app.kubernetes.io/component`. A component's replica count therefore cannot exceed the
  node count. On a two-node cluster that means the third ingester **and** one replica of
  every two-replica component (distributor, querier, query-frontend, query-scheduler,
  index-gateway, ruler) stay `Pending` — the ingester ring never reaches its replication
  factor, and each other component silently degrades to a single serving replica,
  losing the single-pod-loss survival this component exists to provide.
- **Metrics scrape wiring.** Every workload exposes Prometheus metrics on its
  `http-metrics` port (`3100`), but this artifact contains **nothing that causes them to
  be scraped**: it ships no `ServiceMonitor`, no `PodMonitor`, no scrape configuration,
  and no bundled metrics agent (the chart's `monitoring.serviceMonitor` and its
  `selfMonitoring` agent are both switched off — see § Why this topology). Making the
  metrics land in a metrics store is therefore entirely the consumer's job: it points
  its own collector (`observability/alloy`) at those endpoints, or supplies its own
  `ServiceMonitor`s if it runs a prometheus-operator-based stack. Shipping either here
  would bind the artifact to prometheus-operator CRDs it otherwise does not need.
  Recording and alerting rules for Loki are likewise not shipped and are owned the same
  way.
- **Grafana dashboards.** This artifact ships **no dashboards** and no dashboard
  `ConfigMap`s (the chart bundles a set; it is switched off by the same `monitoring`
  block that disables the scrape resources above — one chart key, two distinct
  ownership questions). Dashboard provisioning is a consumer concern, handled through
  the catalog's Grafana components (`observability/grafana`,
  `observability/grafana-operator`) and the consumer's own overlay. A consumer that
  wants the upstream Loki dashboards imports them there rather than re-enabling
  anything in this component.
- **A per-cluster sizing overlay** where the platform defaults do not fit — replica
  counts and resource envelopes are the expected `source.kustomize.patches` surface.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor), and
  the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave` annotation)
  — Argo definitions live in the consumer cluster repos, not here.

Path-style addressing (`s3forcepathstyle: true`) is baked into the workload (the
self-hosted / path-style S3 standard — MinIO, Garage and similar require it) and is not
consumer-tunable.

### Durability note

Committed chunks live in the S3 object store and survive pod and node loss. The
component ships **no** `PersistentVolumeClaim`s and declares no `volumeClaimTemplates`
anywhere — nothing in this artifact requests durable storage. As rendered, five
workloads (`ingester`, `querier`, `index-gateway`, `compactor`, `ruler`) mount an
`emptyDir` at `/var/loki` as their working directory, and the compactor and ruler each
mount one further `emptyDir` for scratch space. The remaining three (`distributor`,
`query-frontend`, `query-scheduler`) mount no data volume at all — they are pure
request-path processes whose only volumes are the two config `ConfigMap`s.

The un-flushed write window is protected by `replication_factor: 3` across three
ingesters — losing any single ingester loses no data, because two other replicas hold
the same streams. A **simultaneous** loss of all ingesters (or a full-cluster restart)
does lose the not-yet-flushed window. A consumer that wants that window on disk needs a
catalog change enabling ingester persistence, not an overlay: `volumeClaimTemplates`
cannot be added to a live `StatefulSet`.

## Namespace & Pod Security

The component ships a dedicated `loki-distributed` `Namespace`
(`manifests/00-namespace.yaml`, sole-claimant rule) carrying
`pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the strictest posture the workload provably satisfies — derived from the
rendered manifest and checked against **all eight** component pod templates, not one:

- **Pod**: `runAsNonRoot: true` + `seccompProfile: RuntimeDefault`. The chart's pod
  default omits `seccompProfile` (which would cap the namespace at `baseline`), so the
  helm values add it explicitly.
- **Container**: `allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]` +
  `seccompProfile: RuntimeDefault` (+ `readOnlyRootFilesystem`, `runAsNonRoot`,
  `runAsUser: 10001`).
- **No Baseline-forbidden field** anywhere in the render: no `hostPath` volume, no host
  namespace, no privileged container, no host port.

With the rule sidecar disabled, every pod is a single container, so the restricted
container predicates hold for every container in every pod.

## Sync-wave

`10` — Loki needs the cluster's S3 endpoint plus the chunks/ruler buckets (the
`s3-object` capability). The log collector `observability/alloy` (sync-wave 20) forwards
to this component, so it comes after.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/loki-distributed:0.1.0
```

The OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips a leading
`v`); the corresponding git tag is `observability/loki-distributed-v0.1.0` (kept
distinct — registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0007 — Platform object store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0021 — Capability layer model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)

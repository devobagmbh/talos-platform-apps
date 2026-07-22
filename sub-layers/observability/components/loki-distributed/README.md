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

`swap_class` scores substituting the **tool** (e.g. `loki` → `victoria-logs`), not the
move between this component and its SingleBinary sibling: swapping the *store* is a
`data-migration` (the chunks must be migrated), swapping the *query endpoint* is
`drop-in` (LogQL-compatible). The capability index is tool-keyed, so both Loki
components legitimately claim these ids; the sibling move is a separate axis, costed in
§Relationship below.

## Relationship to `observability/loki`

`observability/loki` ships the **same chart at the same version** in `SingleBinary`
mode — one `StatefulSet`, one replica — for single-node consumers. This component is the
**second, independently versioned** artifact: a multi-node consumer selects highly
available log storage by pointing its Argo `Application` at `observability/loki-distributed`
**instead of** `observability/loki`. The two are alternative topologies of one store and
are not run together. Each ships its own dedicated namespace, which keeps two Argo
`Application`s from contending over the same **Kubernetes** objects — it does **not**
separate the S3 buckets, which stay shared state (§Failure modes and recovery).

Switching between the two is **consumer-change-shaped with no data migration**: both
renders emit an identical `schema_config` (tsdb / v13 / prefix `loki_index_` / 24h from
`2024-04-01`), so the new component reads the existing buckets as they are. What a
consumer actually changes:

| | `observability/loki` | `observability/loki-distributed` |
|---|---|---|
| OCI repo | `…/observability/loki` | `…/observability/loki-distributed` |
| Namespace | `loki` | `loki-distributed` |
| Write endpoint | the single `loki` `Service` | `loki-distributed-distributor` |
| Read endpoint | the same `loki` `Service` | `loki-distributed-query-frontend` |
| Config refs | `loki-runtime-config` / `-secret` | `loki-distributed-runtime-config` / `-secret` |

The ref **names** are component-scoped, but the **keys inside them are byte-identical**,
so a consumer already supplying the SingleBinary component's S3 values reuses them
verbatim (see §Freeze-line). Read the cut-over procedure in §Failure modes and recovery
before switching — the buckets are shared state and the two components must not run
against them concurrently.

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

In aggregate that is **16 pods** where the SingleBinary sibling runs 1, requesting
**1.9 CPU cores and 9.5 GiB of memory** (13 GiB of memory limits) before any consumer
resizing — the price of the HA topology, and the number to check a cluster against
before selecting this component over `observability/loki`.

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

Two upstream-chart quirks in that set, both harmless but both alarming on a first read.
`query-frontend`, its `-headless` sibling and `query-scheduler` set
`publishNotReadyAddresses: true` so the query components can discover each other before
readiness — the consequence is that a restarting query-frontend is in DNS before it can
serve, so brief query errors during a rollout are expected, not a fault. And the
compactor's `spec.serviceName` names a `loki-distributed-compactor-headless` that is
never emitted; Kubernetes does not require the governing `Service` to exist, and the
single compactor is reached over its `ClusterIP` `Service` — which is what
`common.compactor_grpc_address` resolves. The other three `StatefulSet`s resolve
`spec.serviceName` to a real headless `Service`.

The chart ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does not apply
and there is no `-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Why this topology

### Why `Distributed` and not `SimpleScalable`

The chart offers a middle mode, `SimpleScalable` (three targets: read / write / backend),
and it was a genuine candidate — it would also survive single-pod loss, with noticeably
fewer workloads than the 16 pods above. It was rejected for two reasons. First,
observability of Loki itself: the upstream `loki-overview` mixin selects on the
microservices job names (`distributor`, `ingester`, `querier`, …) that only `Distributed`
produces, so under `SimpleScalable`'s read/write/backend targets those dashboards and
rules do not match. Second, stack consistency: `observability/mimir` already runs the
equivalent microservices shape in this stack, so `Distributed` keeps one operational
model across the metrics and logs stores rather than two.

### Replica counts inside `Distributed`

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
limit (a CPU limit only throttles; memory is the incompressible OOM risk). The values are
a platform starting point for a modest multi-node cluster. They are **not** consumer-
tunable today: this component declares no `resource_policy`, which
`schemas/compatibility.schema.json` treats as class `fixed`, so resizing is a catalog
change rather than an overlay (ADR-0024 Resource-Sizing / docs#159 is the axis that
would open it). Replica counts *are* overlay surface.

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

Not everything about the S3 connection is consumer-owned: path-style addressing
(`s3forcepathstyle: true`) sits on the catalog side of the freeze-line, baked into the
workload because it is the self-hosted / path-style S3 standard that MinIO, Garage and
similar require. It is not consumer-tunable.

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
  losing the single-pod-loss survival this component exists to provide. **Four or more
  nodes** are RECOMMENDED if the cluster is ever drained for maintenance — see §Failure
  modes and recovery.
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
- **Network isolation.** `auth_enabled: false` (single-tenant) and no shipped
  `NetworkPolicy` together mean any pod with cluster-internal reach to the
  query-frontend or querier `ClusterIP` can read every log line from every namespace.
  That is the correct catalog default — the isolation boundary is a cluster-topology
  decision — but it makes restricting access a consumer obligation, via `NetworkPolicy`
  or a Cilium `CiliumClusterwideNetworkPolicy`.
- **A per-cluster replica overlay** where the platform defaults do not fit — replica
  counts are the expected `source.kustomize.patches` surface. Container resources are
  not (class `fixed`; see §Why this topology).
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor), and
  the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave` annotation)
  — Argo definitions live in the consumer cluster repos, not here.

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
the same streams. A consumer that wants that window on disk needs a catalog change
enabling ingester persistence, not an overlay: `volumeClaimTemplates` cannot be added to
a live `StatefulSet`.

## Failure modes and recovery

**Full-cluster restart.** Losing all ingesters at once (the one case
`replication_factor: 3` does not cover) costs only the not-yet-flushed window; every
chunk already written to S3 is intact, so if the object store is healthy there is
nothing to restore and the component recovers by starting up. The size of the gap is
bounded by the ingester's chunk idle/flush timing — this component overrides neither
`chunk_idle_period` nor `max_chunk_age`, so Loki's upstream defaults for the pinned
appVersion are what an operator sizes the gap from; a LogQL query spanning the restart
shows the actual extent.

**Compactor downtime.** While the singleton compactor is unscheduled, compaction and
retention enforcement pause; writes and queries are unaffected and no data is lost. The
exposure is the reverse of data loss — objects past the retention window keep existing
instead of being pruned, so downtime approaching the retention period needs attention
(storage growth, and data that policy says should be gone). Recovery needs no restore:
the compactor re-reads its state from S3 on restart and holds no local cache worth
preserving.

**Node maintenance on exactly three nodes.** Draining one node evicts an ingester that
cannot be rescheduled — the hard anti-affinity leaves no eligible node — so it stays
`Pending` for the duration of the drain. Writes continue on the remaining two ingesters,
but ingester fault tolerance during that window is **zero**: one more fault breaks the
write path. Run four or more nodes if the cluster is drained as a matter of routine.

**Cut-over from `observability/loki`.** The two components share the S3 buckets, and the
namespace separation protects Kubernetes objects only. Running both **at the same time
against the same chunks/ruler buckets corrupts the TSDB index**, because two compactors
mutate the same objects. The supported path is therefore a **sequential** cut-over: stop
the old Argo `Application`, confirm its pods are gone, then start the new one against
the **same** buckets — no data migration, because both renders emit an identical
`schema_config`. Distinct buckets are needed only if a consumer deliberately wants an
overlapping window with both components live, and that is a separate data-migration
exercise, not the cut-over path.

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

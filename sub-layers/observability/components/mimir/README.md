# Component `observability/mimir`

[Grafana Mimir](https://grafana.com/docs/mimir/latest/) — the platform **metrics
store** and **PromQL query endpoint** (OSS, AGPL-3.0). Deployed in the **classic
microservices architecture** (the `mimir-distributed` chart 5.x, no Kafka), every core
component at one replica, backed by an **S3-compatible object store** (the `s3-object`
capability) for both the TSDB blocks and the ruler. Mimir is the long-term metrics
analogue of `observability/loki` (logs).

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

Disabled (not needed for the small single-node footprint): `minio` (external S3 is used
instead of the chart's bundled minio), `nginx`/`gateway` (a consumer fronts Mimir via
its own gateway),
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

Beyond those, the same ConfigMap carries **optional** keys — the artifact ships a working
default for each, and a consumer sets them only to change behaviour (`optional.env_keys` in
`customization.yaml`): the two ring replication factors, the nine query-path cache keys,
and `RULER_ALERTMANAGER_URL`. See [High availability](#high-availability) below.

**`RULER_ALERTMANAGER_URL`** — the built-in alertmanager is disabled (the platform uses a
standalone one), so the ruler must be pointed at the consumer's Alertmanager (e.g.
`http://alertmanager-operated.monitoring.svc:9093`). Unset → empty → the ruler evaluates
rules but does not notify (safe default).

## High availability

The artifact ships a **single-node** shape and reaches an **HA** shape through
consumer-side overlay only — no catalog PR, no replacement of the signed config. Both
shapes come from the same artifact.

### Prerequisites — read before scaling

- **A node-independent StorageClass.** The ingester and store-gateway PVCs declare no
  `storageClassName` and bind the cluster default. With a node-pinned default
  (`local-path-provisioner` and friends) a lost node takes the un-compacted WAL with it,
  and a pod whose PVC is bound to that node cannot be rescheduled anywhere else.
- **Three schedulable nodes, minimum.** Below that, the hard anti-affinity leaves surplus
  replicas `Pending` — correctly.
- **A fourth node for maintenance without loss of redundancy.** On exactly three, drain →
  service → uncordon → wait for the ingester to rejoin → next node works, but the whole
  window runs at reduced redundancy.

### The two supported shapes

| Role | Single-node (shipped) | HA |
|---|---|---|
| ingester | 1, RF 1 | 3, RF 3 |
| store-gateway | 1, RF 1 | 3, RF 3 |
| distributor / querier / query-frontend / query-scheduler | 1 | 2 |
| compactor / ruler | 1 | 1 — **not** redundant, see below |

### Scaling out — order matters

1. Raise the replica counts (consumer overlay, `source.kustomize.patches`).
2. **Wait until every ingester reports `ACTIVE`** in `/ingester/ring` **and every
   store-gateway is registered and healthy** in `/store-gateway/ring`. Both rings, not
   just the ingester one — each factor has its own ring and its own instance count, and
   raising the store-gateway factor over a ring that has not caught up fails historical
   queries exactly the way the ingester case fails writes.
3. Only then raise `INGESTER_REPLICATION_FACTOR` and `STORE_GATEWAY_REPLICATION_FACTOR`.

The reverse order reproduces the state of #379: a replication factor above the number of
live ring instances makes every write and query fail with *"too many unhealthy instances in
the ring"*. Note this is about the **instance count**, not the quorum — RF 3 needs three
distinct ring members, not merely the two that satisfy its quorum.

Raising the factor is **not retroactive**: it applies to samples received from then on
(including further samples for series that already exist), never to data already written.
Blocks already in object storage are unaffected — their durability is a property of the
object store, not of the Mimir ring.

### Applying a config change

The keys arrive via `envFrom`, so **a changed ConfigMap restarts nothing by itself** —
and Kubernetes will not restart those pods on its own either. Without an explicit trigger
the old value stays in place indefinitely.

Do **not** use `kubectl rollout restart`: it writes an uncommitted pod-template annotation
that a self-healing Argo `Application` reverts. Carry a config-generation annotation on the
pod templates in your overlay and bump it together with the ConfigMap.

Express that annotation as a **strategic-merge** patch, not as a JSON-6902 `add`: JSON Patch
has no create-parent semantics, so an `add` of
`/spec/template/metadata/annotations/config-generation` fails outright on any pod template
that carries no `annotations` object — and it replaces nothing gracefully when the chart's own
`checksum/config` annotation is there. A merge creates the map when it is missing and adds to
it when it is not.

Use **two syncs, not one**:

1. sync 1 — replicas only, no config change;
2. sync 2 — the replication factors plus the annotation bump.

**Cross-role ordering is not enforceable from a consumer overlay.** Argo places all eight
controllers in the same wave, and per-resource sync-waves are catalog-owned, so the roles
roll concurrently, each controller one pod at a time.

That is survivable for the roles sync 1 brought to ≥2 replicas. It is **not** for the two
the HA shape keeps at 1: the compactor StatefulSet has no surge capacity, so compaction
pauses while its pod is replaced, and the sole ruler stops evaluating rules for the same
window. Neither loses data — the compactor resumes, and rules are evaluated late rather
than never — but do not read the table below as "HA in every role". Raise those two
yourself if the gap matters; the artifact does not stop you.

Both desync directions are anti-patterns: bumping the annotation without a config change is
a pointless full roll; changing the config without bumping it means the new value never
takes effect, `/config` keeps reporting the old one, and nothing errors. The mechanically
coupled alternative — generating the ConfigMap with a content-hash suffix so the reference
itself changes — removes both, at the cost of a more involved overlay.

### The residual risk, stated plainly

Between the ConfigMap change and the last pod restart, ring clients disagree about the
replication factor. Samples written through a not-yet-restarted distributor land at the old
factor; if the single ingester holding them fails before compaction, they are gone, with no
client-visible error. No upstream guarantee that mixed-factor operation is benign was found
while building this. Keep the window short and avoid it during high write volume.

**The window is bounded during a planned change and unbounded otherwise.** Any unplanned
restart — an OOM kill, an eviction, a drained node, a rescheduled pod — re-resolves that one
pod against whatever the ConfigMap currently says, so a single client can sit on a different
factor indefinitely. Nothing surfaces the disagreement: each pod's `/config` looks
self-consistent and the ring page shows members, not their factors. Making that observable
is tracked in #803. Until it is, treat "did every pod restart?" as an operator
responsibility rather than something the platform will tell you.

### Rolling updates

The guarantee is the StatefulSet's ordered `RollingUpdate` plus readiness gating (one pod
replaced at a time, the next only after the previous is Ready), together with
`unregister_on_shutdown: false`, which lets a restarting ingester keep its ring tokens.

It is **not** the PodDisruptionBudgets. Those gate the **eviction** API — a node drain —
and a controller-driven rollout does not consult them. Both mechanisms are needed, for
different events.

Zone-aware replication is the alternative and is deliberately not taken: it requires as many
real failure domains as the replication factor, changes the rendered shape into per-zone
StatefulSets, and would break the single-node default. Pseudo-zones on one rack are not
failure domains.

### Scaling in — the dangerous direction

Follow [upstream's ingester scale-down procedure][mimir-scale]. What is specific here:

- A replica decrement removes the **highest ordinal** — drain *that* instance, not an
  arbitrary one.
- `podManagementPolicy: Parallel` on the ingester means a bulk decrement terminates several
  pods at once. Reduce **one ordinal at a time**.
- `POST /ingester/shutdown` flushes, ships **and unregisters**, so **no manual ring forget
  is needed for an ingester**. A removed **store-gateway** does not unregister
  (`unregister_on_shutdown: false`), so its entry lingers: either forget it explicitly, or
  wait it out — upstream lets the ring drop it after ten heartbeat timeouts. Forgetting is
  faster; waiting avoids a manual ring mutation.
- Never take the store-gateway below its replication factor, and at most two at a time.

### Rolling back to single-node

**Lower the replication factors first**, while all three replicas are still running, and
let every pod restart onto the new value. Only then decrement, one ordinal at a time.

The tempting order — shrink first, lower the factor at the end — breaks at the *first*
step, not the last: `/ingester/shutdown` unregisters the instance, so 3 → 2 at RF 3 leaves
two ring members for a factor of 3. That is the same "factor above the live instance count"
condition described under scaling out, and writes and queries fail until the factor comes
down. RF 3 needs three members; the fact that its quorum is 2 does not help.

Lowering the factor early does widen the single-copy window — that is the cost, and it is
the smaller one.

### Caches

The catalog ships no memcached — the consumer brings one and names its address. Nine keys,
in four groups — backend and addresses for each of the three bucket-store caches, and three
for the results cache (`customization.yaml`):

| Cache | Buys you | Default |
|---|---|---|
| chunks | fewer object-store reads for recent chunks | off |
| index | fewer index-header lookups | **`inmemory`** (Mimir's own default) |
| metadata | fewer bucket metadata round-trips | off |
| results | reuses query results across identical queries | off |

These are the **query-path** caches. Mimir's ruler-storage cache is deliberately not exposed:
it sits on the alerting path, where a redirected cache address means rule evaluation over
attacker-supplied data rather than a slow dashboard, and rule groups are small enough that
the cache buys little. Whether to expose it at all is tracked in #805.

Two non-obvious points. The **results cache needs three keys** — backend, addresses and
`RESULTS_CACHE_ENABLED`; setting only the first two yields a configured but inert cache with
no error. And because the placeholder default fires on an *empty* value too, setting
`INDEX_CACHE_BACKEND=""` yields `inmemory` again — **disabling the index cache is not
reachable through this knob**, which is acceptable because `inmemory` is a working default.

**Trust note.** Mimir *consumes responses* from the address you name, and memcached is
unauthenticated plaintext: a wrong or redirected address can leak queried data and serve
fabricated results that your alerting rules then evaluate. Keep the endpoint in-cluster and
constrain egress with a `CiliumNetworkPolicy` in your cluster — the catalog cannot author
one, because the address is supplied at runtime. Your memcached must also accept at least
the configured `max_item_size` (1 MiB for chunks and metadata, 5 MiB for index and results),
or larger items are dropped silently.

A memcached backend with an **empty** address list fails loudly at startup (*"no memcached
addresses provided"*). A **wrong but resolvable** address does not — it degrades.

### Value hygiene

Placeholder values are substituted **verbatim into the config text** (newlines are stripped)
and must be plain YAML scalars. Concretely: no leading `|`, `>`, `&`, `!`, `~`, `%` or `*`,
and no space-then-`#` (which starts a YAML comment) — those produce a **silently** wrong value (an empty scalar, an anchor, a null,
a truncation) rather than an error. Only some malformations produce a parse error.

### Upgrading an existing installation

Any change to this component's config changes the `mimir-config` ConfigMap, hence its
checksum, hence **all eight workloads roll**.

At the shipped default of one replica per role, the three StatefulSets — ingester,
store-gateway, compactor — necessarily have a gap: their single pod is terminated before
its replacement starts. The five Deployments render `maxUnavailable: 0` with surge, so
their existing pod stays until the replacement is Ready. The ingester gap is the one that
costs: it traverses the WAL-replay path (see the memory sizing note in `helm/mimir.yaml`),
which is the peak-memory moment. Check ingester memory headroom against your current
cardinality first, and sync during a maintenance window.

**Already scaled past your node count?** The hard anti-affinity is new: surplus ingester or
store-gateway replicas will go `Pending` on the next sync. With a node-pinned StorageClass,
adding a node does **not** release them — their PVC still binds them to the old node. The
remedy is to flush and delete that PVC, or to move to a network-attached StorageClass.

### Resource starting point

Per-pod memory does **not** drop as you scale: with RF 3 across exactly three ingesters,
every ingester holds every series, so the total roughly triples. Treat upstream's
`small.yaml` as the 1M-series datapoint and size from your own cardinality. The sizing
discussion is tracked in #442 / #455 / #458.

### Anti-patterns

- Raising the replication factor before the replicas.
- A replication factor above the replica count.
- An even replication factor (RF 2 → quorum 2 → tolerates zero failures).
- Relying on the stateless roles' soft spread for node-loss tolerance — it permits
  co-location by design.
- A bulk ingester decrement, or draining an ordinal other than the highest.
- Treating pseudo-zones on one rack as failure domains.
- Either annotation/ConfigMap desync direction.

[mimir-scale]: https://grafana.com/docs/mimir/latest/manage/run-production-environment/scaling-out/

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none
of these:

- **`mimir-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` — **`HOST:PORT`, not a
  URL**, e.g. `garage.<namespace>.svc.cluster.local:3900`. Mimir's S3 client is
  `thanos-io/objstore`, which rejects a scheme outright (`Endpoint url cannot have fully
  qualified paths`); the affected Mimir processes then fail to start on the usage-stats
  bucket client. `http` vs `https` is selected by `S3_INSECURE`, never by this value. The form
  is **not uniform across the catalog** and must not be copied between components: deployed
  against a local S3 backend, `loki-distributed` comes up with an `http://` prefix, while
  `tempo-distributed` fails exactly as Mimir does. Further: `S3_REGION` (S3 region; the
  Garage impl uses `garage`), `S3_BUCKET_BLOCKS`, `S3_BUCKET_RULER`, and `S3_INSECURE` —
  the S3 endpoint TLS mode: `"false"` = TLS/HTTPS to the S3 endpoint (default, secure);
  `"true"` = plain HTTP, for a TLS-less S3 endpoint (e.g. an internal NAS).
- **`mimir-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY` (the S3 credentials).
- **The required buckets** — a blocks bucket and a ruler bucket — must exist in the
  `s3-object` backend before the workload runs; their names are what `S3_BUCKET_BLOCKS` /
  `S3_BUCKET_RULER` point at. The platform's active impl (Garage) provisions them via
  `storage-objects/garage-buckets` (sync-wave 10), not the `garage` workload (wave 0).
  NOTE: the buckets MUST exist before Mimir can write — the ingester/compactor/store-gateway
  CrashLoop on a missing S3 bucket until it appears (a visible, self-healing failure).
  Since `garage-buckets` and `mimir` share sync-wave 10, the consumer MUST ensure
  bucket readiness, e.g. by ordering `garage-buckets` ahead of `mimir` in its
  composition.
- **Persistent storage** — the ingester / store-gateway / compactor `StatefulSet`s bind
  their data volume claims to the cluster's default StorageClass; tune the chart
  `persistence` values in the consumer overlay if a specific class/size is needed. NOTE
  (DR): committed blocks live in the S3 object store and survive pod/node loss; the PVCs hold
  the ingester WAL + the store-gateway/compactor working set (recent, not-yet-flushed
  data), so deleting a `StatefulSet` (Argo prune / re-install) loses the recent
  pre-flush window. For planned maintenance, flush before deletion. Recovery: on
  restart the ingester replays that WAL in memory before it goes Ready — at the
  4Gi / 600k-series profile (see the ingester `resources` block) this replay is the
  peak-memory, slowest-recovery moment, taking O(minutes); a larger cardinality ceiling
  widens the window. Operator action for a planned restart / prune / node drain: flush
  the ingester WAL first, then watch the readiness probe return before proceeding, so
  replay does not stack with live ingestion.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor),
  and the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

Path-style addressing is baked into the workload (forced via `bucket_lookup_type: path`
— the self-hosted / path-style S3 standard; MinIO, Garage and similar require it) and is
not consumer-tunable. The S3 endpoint TLS mode is consumer-owned via `S3_INSECURE`
(`insecure: ${S3_INSECURE}`): unset or `"false"` keeps TLS on (the secure default),
`"true"` selects plain HTTP for a TLS-less S3 endpoint. The connection *values* are
consumer-supplied.

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

`10` — Mimir needs the cluster's S3 endpoint + the blocks/ruler buckets (s3-object
capability; the platform's Garage impl provides them at sync-wave 0/10). The metrics
collector `observability/alloy` (sync-wave 20) forwards to Mimir, so it comes after.

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

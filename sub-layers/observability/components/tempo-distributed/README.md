# Component `observability/tempo-distributed`

[Grafana Tempo](https://grafana.com/docs/tempo/latest/) — the platform **trace store** and
**trace-query endpoint** (OSS, AGPL-3.0), deployed in the chart's **microservices
(distributed)** topology for **high availability**: each Tempo target runs as its own
workload, backed by an **S3-compatible object store** (the `s3-object` capability) for the
trace blocks, ingesting **OTLP**.

It implements **two** capabilities in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Trace storage | `traces-storage` | `data-migration` |
| Trace query endpoint | `traces-query` | `drop-in` |

A consumer can substitute another implementation (e.g. `jaeger`) per the index
`swap_class` — swapping the *store* is a `data-migration` (the trace blocks must be
migrated), swapping the *query endpoint* is `drop-in`. These ids and `swap_class` values
are identical to the monolithic sibling's, so moving between the two topologies is a
capability-level no-op.

## Relationship to `observability/tempo` (topology variant)

This is a **topology variant** of the monolithic `observability/tempo`
(AGENTS.md § Sub-layer conventions → Topology variants). The bare name `tempo` denotes the
default/primary topology (monolithic single-binary, one `StatefulSet`, for single-node
consumers); `tempo-distributed` is the HA microservices topology a **multi-node** consumer
picks instead. The two are **mutually exclusive** — a consumer selects exactly one — and
each ships its own dedicated namespace, so they never contend over the same objects.

Both topologies pin the **same Tempo binary** (appVersion `2.10.7`) and write the **same S3
bucket layout**, so the monolithic ↔ distributed move needs **no data migration**. That
per-topology move is a distinct axis with no field in the current compatibility schema; it
is documented here rather than as a schema field (a per-topology swap field would be an
ADR-0021 change).

## Chart source & version pin (ratify on review)

This component renders the `tempo-distributed` chart from the **`grafana-community`** Helm
repo (`https://grafana-community.github.io/helm-charts`, version `2.26.2`, appVersion
`2.10.7`), the actively-maintained successor to the org-migrated `grafana/tempo-distributed`
(the 2026-01-30 governance move documented on the monolithic sibling `observability/tempo`).

`tempo` and `tempo-distributed` are **different upstream charts** with independent version
lines, so the topology-variant rule's literal "identical chart version at introduction"
clause (written for the same-chart Loki case) cannot apply here. The faithful realization
of that clause's **intent** is **appVersion alignment**: chart `2.26.2` is the newest
`tempo-distributed` revision still carrying appVersion `2.10.7` — the same Tempo binary the
monolithic sibling pins. The `3.0.x` chart line carries the newer Tempo `3.0.2` binary and
is deliberately **not** adopted, because aligning the binary keeps a consumer swap between
the two topologies free of a Tempo version boundary (AC2 no data migration, AC3 capability
no-op). VERIFY at push that `2.26.2` is still the top of the `2.10.7` line:
`helm show chart tempo-distributed --repo https://grafana-community.github.io/helm-charts --version 2.26.2`.

## Contents

A `kind: helm` wrapper over the `tempo-distributed` chart (`grafana-community`, version
`2.26.2`, appVersion `2.10.7`) plus `manifests/00-namespace.yaml`. The rendered workload is
the **minimum HA set** — **5 workloads / 10 pods** running
`docker.io/grafana/tempo:2.10.7` (the image is pinned to the chart appVersion, never
`:latest`):

| Role | Kind | Replicas | Path | Notes |
|---|---|---|---|---|
| distributor | `Deployment` | 2 | ingest | OTLP write entrypoint; stateless |
| ingester | `StatefulSet` | 3 | ingest | ring `replication_factor: 3`; holds the recent WAL |
| querier | `Deployment` | 2 | query | stateless query executors |
| query-frontend | `Deployment` | 2 | query | read entrypoint; splits/queues queries |
| compactor | `Deployment` | 1 | neither | compacts blocks in the object store |

Plus per-role `Service`s (and headless discovery Services), a `ServiceAccount`
(`automountServiceAccountToken: false` — Tempo needs no Kubernetes API access), the four
`PodDisruptionBudget`s that carry `maxUnavailable: 1` (distributor, ingester, querier,
query-frontend — the roles with replicas > 1), and the chart-generated tempo config
`ConfigMap`.

**HA (AC1).** The ingest path (distributor → ingester) and the query path (query-frontend →
querier) each run ≥ 2 replicas with a `maxUnavailable: 1` PDB, and the ingester's ring
`replication_factor: 3` across 3 replicas keeps the write quorum (2) when one ingester is
lost — so both paths survive the loss of any single pod. The **compactor runs a single
replica**: it sits on neither the ingest nor the query path, so its momentary loss (until
rescheduled) pauses only compaction/retention — writes and queries continue — and it is the
minimum that satisfies AC1. (Tempo's compactor CAN scale horizontally via the ring, unlike
Loki's singleton; a consumer raises it per-cluster.)

**Receivers — OTLP only.** Alloy forwards OTLP traces to Tempo (design issue #183), so the
rendered ingestion config (`distributor.receivers`) enables **only** the OTLP gRPC
(`:4317`) and HTTP (`:4318`) receivers. Unlike the monolithic sibling (whose chart
hard-dereferenced jaeger and forced a frozen config-string copy), the `tempo-distributed`
chart renders both the receiver config **and** the distributor `Service` ports fully
conditionally, so with only `traces.otlp.*` enabled **no** jaeger/zipkin ports appear
anywhere — no config-string override is needed.

**Disabled** (kept OFF beyond the minimum HA set — issue #731 Boundaries):

- **memcached caches** (`memcached.enabled: false`) — the chart default is `true`; disabling
  drops a memcached `Deployment` and the memcached/exporter images. The config `cache:` block
  renders empty.
- **metrics-generator** (`metricsGenerator.enabled: false`) — would add a workload and need a
  Prometheus remote_write target.
- **gateway** (`gateway.enabled: false`) — would add an unpinned nginx image and a second
  ingress surface; consumers target the component's own Services directly (distributor for
  the write path, query-frontend for the read path).
- Also restated OFF (chart-default-off, pinned against a chart flip): the bundled MinIO, the
  rollout-operator, the meta-monitoring `ServiceMonitor`/grafana-agent, and the
  `PrometheusRule` (all CRD-dependent or workload-adding).

The chart ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does not apply and
there is **no** `-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Resource-cost delta vs `observability/tempo` (AC6)

The monolithic `observability/tempo` runs **1 pod** (one `StatefulSet` replica, every Tempo
target in a single process). This distributed variant runs **10 pods across 5 roles**
(distributor ×2, ingester ×3, querier ×2, query-frontend ×2, compactor ×1) plus the per-role
Services and PDBs. That is the cost of surviving single-pod loss on the ingest and query
paths; it is why the monolithic topology remains the right choice for single-node consumers
and this variant is for **multi-node** clusters. Per-role resource requests/limits are a
modest-cluster starting point (each carries `requests.cpu` + `requests.memory` +
`limits.memory`, no cpu limit); a consumer raises them per-cluster via its Argo Kustomize
overlay (ADR-0024).

**Consumer-side, out of scope here:** scrape wiring (`ServiceMonitor`/`PodMonitor`, or Alloy
scrape config) and Grafana dashboards stay consumer-owned — the catalog ships neither.

## Freeze-line (ADR-0024 v2, Shapes a + c)

Tempo is **not** cluster-agnostic: its **S3 connection** (endpoint, region, bucket name,
credentials) is per-cluster and 100% consumer-owned. The freeze-line keeps that connection
out of the frozen workload:

- The **workload** (the rendered Deployments/StatefulSet + Services + PDBs + the tempo config
  `ConfigMap` + the `Namespace`) is catalog-owned and signed.
- The rendered Tempo config references `${VAR}` **placeholders**, not real endpoints/keys.
  Tempo resolves them at runtime from consumer-supplied env via the `-config.expand-env=true`
  flag (wired via the chart's `global.extraArgs`, rendered into every component container's
  args; the consumer-owned env is wired onto every container's `envFrom` via
  `global.extraEnvFrom`).

Two consumer-supplied refs feed the placeholders (key **names** byte-identical to the
monolithic sibling's, so a topology swap reuses the same ConfigMap/Secret contents):

- **Shape (a)** — `ConfigMap` `tempo-distributed-runtime-config` (non-secret), `envFrom`:
  `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_TRACES`, `S3_INSECURE`.
- **Shape (c)** — `Secret` `tempo-distributed-runtime-secret`, `envFrom`: `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.

These map into `storage.trace.s3` (`bucket`/`endpoint`/`region`/`access_key`/`secret_key`/
`insecure`) in the rendered config. NOTE: Tempo uses snake_case S3 keys
(`access_key`/`secret_key`), distinct from Loki's `accessKeyId`. See `customization.yaml`.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none of
these:

- **`tempo-distributed-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` (the explicit S3
  endpoint URL), `S3_REGION`, `S3_BUCKET_TRACES`, and `S3_INSECURE` (S3 endpoint TLS mode:
  `"false"` = TLS/HTTPS, the secure default; `"true"` = plain HTTP for a TLS-less endpoint).
- **`tempo-distributed-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.
- **The required traces bucket** — MUST exist in the `s3-object` backend before the workload
  flushes blocks; its name is what `S3_BUCKET_TRACES` points at. Order bucket provisioning
  ahead of this component in the composition to avoid a first-deploy CrashLoop window.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor), and the
  `audit`/`warn` PSA modes.
- The Argo `Application` CR(s) with `argocd.argoproj.io/sync-wave` annotations — Argo
  definitions live in the consumer cluster repos, not here.

Path-style addressing (`forcepathstyle: true`) is baked into the workload (the self-hosted /
path-style S3 standard — MinIO, Garage and similar require it) and is not consumer-tunable.

## Namespace & Pod Security

The component ships a dedicated `tempo-distributed` `Namespace` (`manifests/00-namespace.yaml`,
sole-claimant rule) carrying `pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the posture the workload provably satisfies — DERIVED from the rendered
manifest and checked against **every** one of the 5 component pod templates:

- **Pod**: `runAsNonRoot: true` + `seccompProfile: RuntimeDefault` (+ `runAsUser`/
  `runAsGroup`/`fsGroup: 1000`). The chart's pod default sets only `fsGroup` and omits
  `seccompProfile` (which would cap the namespace at `baseline`), so the helm values add it.
- **Container**: `allowPrivilegeEscalation: false` + `capabilities.drop: [ALL]` +
  `seccompProfile: RuntimeDefault` (+ `readOnlyRootFilesystem: true`, `runAsNonRoot`). Every
  pod is a single Tempo container; Tempo writes only under the mounted `/var/tempo` data
  volume, so `readOnlyRootFilesystem: true` is safe.
- No Baseline-forbidden field anywhere: no hostPath volume, no host namespace, no privileged
  container, no host port.

`task scan:psa-conformance` is the deterministic check that the workloads conform to the
declared level.

## Sync-wave

`10` — Tempo needs the cluster's S3 endpoint + the traces bucket (`s3-object` capability;
the platform's Garage impl provides them at sync-wave 0/10). The trace forwarder
`observability/alloy` (sync-wave 20) forwards OTLP to Tempo, so it comes after.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/tempo-distributed:0.1.0
```

The OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the leading
`v`); the corresponding git tag is `observability/tempo-distributed-v0.1.0` (kept distinct —
registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md) — this chart ships no CRDs, so no `-crds` split applies
- [ADR-0007 — Platform object store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

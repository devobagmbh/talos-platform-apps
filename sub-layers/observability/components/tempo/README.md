# Component `observability/tempo`

[Grafana Tempo](https://grafana.com/docs/tempo/latest/) — the platform **trace store**
and **trace-query endpoint** (OSS, AGPL-3.0). Deployed in **monolithic single-binary**
mode (one `StatefulSet`, one replica, every Tempo target in a single process) shipped
backed by an **S3-compatible object store** (the `s3-object` capability) for the trace
blocks, ingesting **OTLP** traces.

It implements **two** capabilities in `catalog/capability-index.yaml`:

| Capability | id | `swap_class` |
|---|---|---|
| Trace storage | `traces-storage` | `data-migration` |
| Trace query endpoint | `traces-query` | `drop-in` |

A consumer can substitute another implementation (e.g. `jaeger`) per the index
`swap_class` — swapping the *store* is a `data-migration` (the trace blocks must be
migrated), swapping the *query endpoint* is `drop-in`.

## Chart source (deviation — ratify on review)

This component renders the `tempo` chart from the **`grafana-community`** Helm repo
(`https://grafana-community.github.io/helm-charts`, version `2.2.3`, appVersion
`2.10.7`), **not** `grafana/tempo` from `https://grafana.github.io/helm-charts`. On
2026-01-30 Grafana migrated the `tempo`/`tempo-distributed`/`grafana` charts to the new
`grafana-community` org (a governance move). The old `grafana/tempo` is now a
deprecated dead stub (frozen at chart 1.24.4 / appVersion 2.9.0, no future updates);
`grafana-community/tempo` is the actively-maintained successor — the same monolithic
single-binary chart (`description: "Grafana Tempo Single Binary Mode"`). Evidence:
`grafana-community/helm-charts#2`, `grafana/helm-charts` PR#4104/#4112.

## Why monolithic

The catalog consumers are small single-node clusters. Tempo's distributed topology
(`tempo-distributed` — separate distributor/ingester/querier/compactor deployments plus
a gateway and caches) is massively over-provisioned for that scale. The monolithic
single binary runs the entire ingest + query + compaction path in one container, served
by a single `StatefulSet` pod plus its `Service` and `ServiceAccount` (analogous to the
`observability/loki` SingleBinary mode).

## Contents

A `kind: helm` wrapper over the `tempo` chart (`grafana-community`, version `2.2.3`,
appVersion `2.10.7`) plus `manifests/00-namespace.yaml`:

- A `StatefulSet` (`tempo`, `replicas: 1`) running `docker.io/grafana/tempo:2.10.7` —
  the image is pinned to the chart appVersion, never `:latest` (the chart image tag
  defaults to `.Chart.AppVersion`, not overridden here).
- A `Service` (the Tempo HTTP/gRPC endpoints + the OTLP/jaeger/zipkin receiver ports)
  and a `ServiceAccount` (with `automountServiceAccountToken: false` — Tempo needs no
  Kubernetes API access).
- The chart-generated `tempo` config `ConfigMap`.
- A dedicated `tempo` `Namespace` carrying `pod-security.kubernetes.io/enforce:
  restricted`.

**Receivers — OTLP only.** Alloy forwards OTLP traces to Tempo (design issue #183), so
the rendered ingestion config (`distributor.receivers`) enables **only** the OTLP gRPC
(`:4317`) and HTTP (`:4318`) receivers — the chart's default jaeger/zipkin receivers are
removed from the config. NOTE (chart limitation): the chart's `_ports.tpl` helper
hard-dereferences `tempo.receivers.jaeger.protocols.*` to build the `Service`, so the
jaeger/zipkin **Service ports still render** even though the config does not enable
them — they are harmless (nothing forwards to them). Removing them entirely would
require patching the upstream chart; the config is the authoritative ingestion surface
and is OTLP-only.

NOTE (maintenance): `helm/tempo.yaml` pins the full Tempo `config:` string (a frozen
copy of chart 2.2.3's `templates/configmap-tempo.yaml`) to deliver OTLP-only ingest.
Every chart version bump for this component MUST include a manual re-diff of the
upstream `templates/configmap-tempo.yaml` against the pinned `config:` string — a new
upstream top-level config block is otherwise silently dropped from the rendered config.

Disabled (not needed for a single-node monolithic store): anonymous usage reporting
(`tempo.reportingEnabled: false` — platform/airgap hygiene), multitenancy
(`tempo.multitenancyEnabled: false` — single-tenant platform store), the bundled
`serviceMonitor` (Alloy scrapes Tempo's metrics endpoint externally —
`observability/alloy`), and `networkPolicy` (a consumer/Cilium concern).

The chart ships **no** CustomResourceDefinitions, so strict-B (ADR-0028) does not apply
and there is no `-crds` companion artifact. The rendered workload contains zero
`kind: CustomResourceDefinition`.

## Freeze-line (ADR-0024 v2, Shapes a + c)

Tempo is **not** cluster-agnostic: its **S3 connection** (endpoint, region, bucket name,
credentials) is per-cluster and 100% consumer-owned. The freeze-line keeps that
connection out of the frozen workload:

- The **workload** (the rendered `StatefulSet` + `Service` + `ServiceAccount` + the
  tempo config `ConfigMap` + the `Namespace`) is catalog-owned and signed — never
  consumer-patched.
- The rendered Tempo config references `${VAR}` **placeholders**, not real
  endpoints/keys. Tempo resolves them at runtime from consumer-supplied env via the
  `-config.expand-env=true` flag (set on the container args; the consumer-owned env is
  wired onto the container's `envFrom`).

Two consumer-supplied refs feed the placeholders:

- **Shape (a)** — `ConfigMap` `tempo-runtime-config` (non-secret), `envFrom`:
  `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_TRACES`, `S3_INSECURE`.
- **Shape (c)** — `Secret` `tempo-runtime-secret`, `envFrom`: `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY`.

These map into `storage.trace.s3` (`bucket`/`endpoint`/`region`/`access_key`/`secret_key`)
in the rendered config. NOTE: Tempo uses snake_case S3 keys (`access_key`/`secret_key`),
distinct from Loki's `accessKeyId` naming. See `customization.yaml`.

## Consumer obligations (out of scope here)

The consumer supplies, in its own cluster repo / Argo overlay — the catalog ships none
of these:

- **`tempo-runtime-config` `ConfigMap`** with keys `S3_ENDPOINT` (the explicit S3
  endpoint URL of the `s3-object` provider, e.g. `https://s3.<consumer-domain>:3900`),
  `S3_REGION` (provider-specific; e.g. `garage` for a Garage backend), `S3_BUCKET_TRACES`,
  and `S3_INSECURE` — the S3 endpoint TLS mode: `"false"` = TLS/HTTPS to the S3 endpoint
  (default, secure); `"true"` = plain HTTP, for a TLS-less S3 endpoint.
- **`tempo-runtime-secret` `Secret`** with keys `S3_ACCESS_KEY_ID`,
  `S3_SECRET_ACCESS_KEY` (the S3 credentials).
- **The traces bucket** — provisioned consumer-side by whatever mechanism the chosen
  `s3-object` provider uses (for a Garage backend that is `storage-objects/garage-buckets`,
  sync-wave 10, not the `garage` workload at wave 0); its name is what `S3_BUCKET_TRACES`
  points at. NOTE: the traces bucket MUST exist before Tempo flushes blocks; consumers
  MUST order the bucket provisioning ahead of `tempo` in their composition (e.g. a lower
  Argo sync-wave on it, or an Argo sync-phase/readiness gate) to avoid a first-deploy
  CrashLoop window — Tempo errors/CrashLoops on the S3 flush against a missing bucket
  until it appears (visible + self-healing).
- **Persistent storage** — the `StatefulSet`'s WAL volume claim binds to the cluster's
  default StorageClass (no `storageClassName` is pinned; consumer-tunable). NOTE (DR):
  committed trace blocks live in the object store and survive pod/node loss; the PVC holds
  only the WAL (recent, not-yet-flushed window) and uses
  `persistentVolumeClaimRetentionPolicy: whenDeleted/whenScaled: Delete`, so deleting
  the `StatefulSet` (Argo prune / re-install) loses the recent pre-flush window. For
  planned maintenance, flush before deletion.
- **PNI labels** — the `platform.io/provide.*` namespace trust anchors, the
  `pod-security.kubernetes.io/enforce-version` pin (its cluster's Kubernetes minor), and
  the `audit`/`warn` PSA modes.
- The Argo `Application` CR itself (with its `argocd.argoproj.io/sync-wave`
  annotation) — Argo definitions live in the consumer cluster repos, not here.

Path-style addressing (`forcepathstyle: true`) is baked into the workload — the standard
for self-hosted S3 (Garage, MinIO, …) — and is not consumer-tunable. The S3 endpoint TLS
mode is consumer-owned via `S3_INSECURE` (`insecure: ${S3_INSECURE}`): unset or `"false"`
keeps TLS on (the secure default), `"true"` selects plain HTTP for a TLS-less S3 endpoint.
The connection *values* are consumer-supplied.

## Namespace & Pod Security

The component ships a dedicated `tempo` `Namespace` (`manifests/00-namespace.yaml`,
sole-claimant rule) carrying `pod-security.kubernetes.io/enforce: restricted` plus the
`platform.devoba.de/{sub-layer,component}` ownership labels.

`restricted` is the posture the workload provably satisfies — confirmed against the
rendered `StatefulSet` pod template:

- **Pod**: `runAsNonRoot: true` + `seccompProfile: RuntimeDefault` (+ `runAsUser`/
  `runAsGroup`/`fsGroup: 10001`). The chart's pod default omits `seccompProfile` (which
  would force a `baseline` floor), so the helm values add it explicitly.
- **Container** (`tempo`): `allowPrivilegeEscalation: false` + `capabilities.drop:
  [ALL]` + `seccompProfile: RuntimeDefault` (+ `runAsNonRoot`).

The pod is a single container (`tempo`), so the restricted container predicates hold for
every container in the pod. NOTE: `readOnlyRootFilesystem` is intentionally **not** set —
Tempo writes scratch/WAL paths and `restricted` PSA does not require it. Enabling it
(with explicit `emptyDir` mounts for the scratch paths) is a deferred hardening item.

## Sync-wave

`10` — Tempo needs the cluster's `s3-object` endpoint + the traces bucket present; for a
Garage backend the foundational `storage-objects/garage` (sync-wave 0) provides the
endpoint and `storage-objects/garage-buckets` (sync-wave 10) the bucket. The trace
forwarder `observability/alloy` (sync-wave 20)
forwards OTLP to Tempo, so it comes after.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/observability/tempo:0.1.0
```

The OCI registry tag at publish is the bare SemVer `0.1.0` (`task push` strips the
leading `v`); the corresponding git tag is `observability/tempo-v0.1.0` (kept distinct —
registry tag vs. SemVer git tag).

## Related ADRs

- [ADR-0015 — Monitoring architecture](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0015-monitoring-architecture.md)
- [ADR-0024 — Customization Contract v2 (freeze-line)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract-v2.md)
- [ADR-0007 — Platform object store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0009 — Platform Layer Model (OCI granularity)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

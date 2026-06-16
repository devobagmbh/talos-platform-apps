# Component `storage-objects/garage`

[Garage](https://garagehq.deuxfleurs.fr/) — a lightweight, S3-compatible object
store for self-hosted, geo-distributed deployments. Implements the **`s3-object`**
capability (instanced S3 object store; `swap_class: drop-in`).

Helm chart `garage` **0.9.3** (appVersion **v2.3.0**), packaged from the upstream
`deuxfleurs-org/garage` git tag `v2.3.0`. There is **no published HTTP Helm repo**
for garage, so the chart is **vendored** as `vendor/garage-0.9.3.tgz` and that
tarball is the mandatory render source (`task render:one` uses the local archive
automatically).

## What ships

- A single-replica **`garage` StatefulSet** running the garage S3 daemon.
- Two **ClusterIP Services** exposing the S3 API (port 3900) and the web endpoint
  (port 3902); the admin API listens on port 3903 on the pod.
- A **ServiceAccount** and **cluster-scoped RBAC** (`ClusterRole` +
  `ClusterRoleBinding`) used by garage's integrated Kubernetes peer discovery.

This component ships **no** ConfigMap or Secret of its own: the runtime config and
the cluster RPC secret are consumer-owned (see Consumer obligations).

## Freeze-line (ADR-0024)

The **workload** (StatefulSet + Services + RBAC) is the signed, pre-rendered
artifact. The runtime config and RPC secret are **100% consumer-owned**: the
catalog sets the chart's `existingConfigMap` / `existingRpcSecret` to the names
below, so the chart renders neither object and the workload references the
consumer's instead.

## Consumer obligations

A consumer MUST supply:

- A **ConfigMap `garage-config`** with key `garage.toml` holding the full garage
  runtime configuration. The init container mounts it at `/mnt/garage.toml`,
  substitutes the RPC secret, and writes the processed file to the path the daemon
  reads. The `garage.toml` content — including the **replication factor**,
  **consistency mode**, **listener / bootstrap topology**, and the **data/metadata
  directories** — is a consumer Layer-3 decision and MUST NOT be baked into the
  catalog artifact.
- A **Secret `garage-runtime-secret`** with key `rpcSecret` holding the shared
  cluster RPC secret. The init container reads it via `secretKeyRef`.

A consumer SHOULD additionally provide:

- **Durable storage** — the catalog default disables persistence (the StatefulSet
  mounts `emptyDir` for metadata and data, so the artifact is cluster-agnostic). A
  consumer that wants durability enables persistence and supplies a `storageClass`
  + PVC sizing in its overlay.
- **External exposure** — both Services are `ClusterIP` by default. Exposing garage
  (a listener VIP via `LoadBalancer`, or an Ingress) is a consumer Layer-3 decision.
- **Replica count** — the StatefulSet defaults to a single replica; multi-node
  garage and its matching replication factor are a consumer topology decision.

## GarageNode runtime CRD behaviour

The chart default `kubernetesSkipCrd: false` is kept. With it, the garage binary is
granted (via the shipped `ClusterRole`) permission to **create the `GarageNode` CRD
(`garagenodes.deuxfleurs.fr`) at runtime** through its integrated Kubernetes peer
discovery. This is upstream's runtime model and is accepted as the catalog default;
because the CRD is created by the running binary, it is **not** a chart-provided
CRD, so the rendered workload contains zero `CustomResourceDefinition` objects and
strict-B (the `-crds` split) does not apply.

A consumer that prefers to manage that CRD out-of-band MAY, in its overlay, set
`garage.kubernetesSkipCrd: true` **and** pre-apply the `GarageNode` CRD before the
workload syncs — this drops the cluster-scoped CRD-creation grant. That is a
consumer Layer-3 decision, not a catalog default.

## Sync-wave

`0` — foundational: it ships the StatefulSet and the S3 endpoint that every bucket
consumer depends on.

## Namespace & Pod Security

Garage ships its own `garage` namespace (`manifests/00-namespace.yaml`) with
`pod-security.kubernetes.io/enforce: baseline` — garage is the sole occupant
(dedicated namespace), so the Namespace object travels with the artifact and a
shipped manifest wins over Argo `managedNamespaceMetadata`. `baseline` is the
strictest level the rendered pod provably satisfies: the pod sets `runAsNonRoot`
and both containers drop all capabilities with a read-only root filesystem, but the
pod omits `seccompProfile: RuntimeDefault` and the containers omit
`allowPrivilegeEscalation: false`, so `restricted` would reject the pods at
admission. A consumer that injects the missing securityContext fields in its overlay
MAY then tighten the namespace to `restricted`.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage:X.Y.Z
```

The published registry tag is the bare SemVer (`X.Y.Z`); the git tag follows the
`storage-objects/garage-vX.Y.Z` pattern.

## Related ADRs

- [ADR-0007 — Platform-Object-Store](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)

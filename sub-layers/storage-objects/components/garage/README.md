# Component `storage-objects/garage`

[Garage](https://garagehq.deuxfleurs.fr/) — a lightweight, S3-compatible object
store for self-hosted, geo-distributed deployments. Implements the **`s3-object`**
capability (instanced S3 object store; `swap_class: drop-in`).

Helm chart `garage` **0.9.3** (appVersion **v2.3.0**), packaged from the upstream
`deuxfleurs-org/garage` git tag `v2.3.0`. There is **no published HTTP Helm repo**
for garage, so the chart is **vendored** as `vendor/garage-0.9.3.tgz` and that
tarball is the mandatory render source (`task render:one` uses the local archive
automatically).

This is the **strict-B WORKLOAD** half (ADR-0028): the `GarageNode`
CustomResourceDefinition ships as the SEPARATE artifact
[`storage-objects/garage-crds`](../garage-crds/README.md) at sync-wave -1. This
workload carries **zero** CRDs.

## What ships

- A single-replica **`garage` StatefulSet** running the garage S3 daemon.
- Two **ClusterIP Services** exposing the S3 API (port 3900) and the web endpoint
  (port 3902); the admin API listens on port 3903 on the pod.
- A **ServiceAccount** and **cluster-scoped RBAC** (`ClusterRole` +
  `ClusterRoleBinding`) carrying ONLY the narrow `deuxfleurs.fr/garagenodes` grant
  used by garage's integrated Kubernetes peer discovery.

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
- **Durable storage.** The catalog default ships `persistence.enabled: false`, so
  the StatefulSet mounts **`emptyDir`** for metadata and data — the artifact is
  cluster-agnostic, but emptyDir is pod-local and ephemeral. A consumer therefore
  **MUST** enable persistence and supply a `storageClass` + PVC sizing in its
  overlay. If it does not, **ALL stored objects and cluster metadata are lost on the
  first pod restart** — an OOMKill, a node drain, or any rolling update destroys the
  data. There is no catalog default that makes garage durable; durability is a
  mandatory consumer obligation.

A consumer SHOULD additionally provide:

- **External exposure** — both Services are `ClusterIP` by default. Exposing garage
  (a listener VIP via `LoadBalancer`, or an Ingress) is a consumer Layer-3 decision.
- **Replica count** — the StatefulSet defaults to a single replica; multi-node
  garage and its matching replication factor are a consumer topology decision (see
  § Scaling from single to multi-node).

## GarageNode CRD — strict-B wiring (ADR-0028)

The catalog default is now **`garage.kubernetesSkipCrd: true`**, which drops the
broad cluster-wide `apiextensions.k8s.io/customresourcedefinitions` create/patch
grant from the shipped `ClusterRole` (CWE-269, least privilege). The narrow
`deuxfleurs.fr/garagenodes` grant the k8s peer-discovery needs is ungated and
stays.

The `GarageNode` CRD (`garagenodes.deuxfleurs.fr`) is therefore **no longer
runtime-created by the garage binary**; it ships as the SEPARATE strict-B artifact
[`storage-objects/garage-crds`](../garage-crds/README.md) at sync-wave -1. The
consumer cluster repo wires **two** Argo `Application`s — the `-crds` app **before**
this workload:

1. **`storage-objects/garage-crds`** Application at
   `argocd.argoproj.io/sync-wave: "-1"` with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting the CRD (and cascading the live `GarageNode` CRs, which would break the
     cluster's peer discovery) when the source removes it. The Helm-layer
     `helm.sh/resource-policy: keep` is **not** honored by Argo for its own prune
     decisions, so `Prune=false` carries it.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit and is the convention for the strict-B `-crds` apps.

2. The workload Application **`storage-objects/garage`** at sync-wave 0, which then
   comes up against a `GarageNode` CRD that already exists.

If a consumer omits the `garage-crds` Application, garage still starts and can
serve S3, but its Kubernetes peer-discovery reconciler fails (the `GarageNode` API
is unknown) — a silent degradation, **not** a crash and **not** data corruption.
Multi-node layouts require the CRD to be present before nodes can register, so both
Applications MUST be wired for any multi-node deployment.

## Scaling from single to multi-node

Order matters when growing from the single-replica default. A wrong order risks
objects written at `replication_factor=1` never being re-replicated:

1. Update the consumer `garage-config` ConfigMap's `garage.toml`
   **`replication_factor`** first.
2. Apply the ConfigMap and **restart** the StatefulSet (see § Config-change rollout)
   so every pod reads the new factor.
3. **Then** scale `replicaCount` to add the new garage nodes.
4. **Then** run `garage layout apply` to assign the new nodes into the cluster
   layout.

## Config-change rollout

The frozen artifact pins a **static** `checksum/config` annotation on the
StatefulSet pod template — it does **not** hash the consumer's `garage-config`
ConfigMap. A change to the consumer-owned `garage-config` ConfigMap therefore does
**not** auto-trigger a StatefulSet rollout. After changing the ConfigMap the
consumer must explicitly run `kubectl rollout restart statefulset/garage` for the
new config to take effect.

## Sync-wave

`0` — foundational: it ships the StatefulSet and the S3 endpoint that every bucket
consumer depends on. The `garage-crds` half precedes it at sync-wave -1.

The shipped `readinessProbe` polls the admin API `/health` on port 3903, which
reports **process** readiness (the daemon is up and the RPC stack is initialised) —
it does **not** guarantee **S3-API functional** readiness. On a fresh cluster the S3
endpoint only serves reads/writes after the consumer has applied a garage layout
(`garage layout apply`). A wave-0 "Healthy" therefore means "garage is running", not
"S3 is serving"; a consumer SHOULD ensure a layout is applied before bucket-consuming
workloads at later sync-waves issue S3 calls.

## Namespace & Pod Security

Garage ships its own `garage` namespace (`manifests/00-namespace.yaml`) with
`pod-security.kubernetes.io/enforce: baseline` — garage is the sole occupant
(dedicated namespace), so the Namespace object travels with the artifact and a
shipped manifest wins over Argo `managedNamespaceMetadata`. `baseline` is the
strictest level the rendered pod provably satisfies: the pod sets `runAsNonRoot`
and both containers drop all capabilities with a read-only root filesystem, but the
pod omits `seccompProfile: RuntimeDefault` and the containers omit
`allowPrivilegeEscalation: false`, so `restricted` would reject the pods at
admission.

To reach `restricted`, a consumer must, in its overlay, set the two missing fields
the rendered pod lacks and then tighten the namespace label:

- pod-level `securityContext.seccompProfile.type: RuntimeDefault`, and
- per-container `securityContext.allowPrivilegeEscalation: false` (on both the
  init container and the garage container).

## RPC secret handling

The init container substitutes the RPC secret into `garage.toml` via an upstream
`sed` pattern, so the secret is **transiently present in the init container's
environment** (`RPC_SECRET`, via `secretKeyRef`) during startup. Exposure is bounded:
the pod's `shareProcessNamespace` defaults to `false` (the garage container cannot
read the init container's process environment) and the processed file lands on a
pod-local `emptyDir`, not a shared or persisted volume.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-objects/garage:X.Y.Z
```

The published registry tag is the bare SemVer (`X.Y.Z`); the git tag follows the
`storage-objects/garage-vX.Y.Z` pattern.

## Related ADRs

- ADR-0007 — Platform-Object-Store
- ADR-0024 — Workload/Config-Freeze-Line
- ADR-0028 — CRD management (strict B)

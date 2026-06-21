# Component `databases/cnpg-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[CloudNativePG](https://cloudnative-pg.io/). It ships **only** the 10
`postgresql.cnpg.io` CustomResourceDefinitions — the CloudNativePG operator
workload (Deployment, RBAC, webhooks) is a **separate** component,
`databases/cnpg`. The two together form the strict-B pair: CRDs first (this
artifact, sync-wave -1), operator after (sync-wave 0).

The CRDs are sourced verbatim from the upstream `cloudnative-pg` Helm chart
**0.28.2** (appVersion 1.29.1). CloudNativePG renders its CRDs as
`crds.create`-gated chart templates (not a `crds/` directory), so this component
is delivered as **raw vendored manifests** (`kind: manifests`) extracted once
from the chart, not as a Helm reference — there is no separate CRDs-only chart.

## What ships

Exactly 10 cluster-scoped resources, all group `postgresql.cnpg.io`:

- `backups.postgresql.cnpg.io`
- `clusterimagecatalogs.postgresql.cnpg.io`
- `clusters.postgresql.cnpg.io`
- `databases.postgresql.cnpg.io`
- `failoverquorums.postgresql.cnpg.io`
- `imagecatalogs.postgresql.cnpg.io`
- `poolers.postgresql.cnpg.io`
- `publications.postgresql.cnpg.io`
- `scheduledbackups.postgresql.cnpg.io`
- `subscriptions.postgresql.cnpg.io`

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD
schemas. The `cnpg-system` Namespace (with its Pod Security Admission
`enforce: restricted` label) stays with the `databases/cnpg` workload artifact;
CRDs are cluster-scoped and require no namespace.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the operator:

1. **`databases/cnpg-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting a CRD (and cascading the consumer's live `Cluster` / `Backup` /
     `Pooler` CRs, which would destroy the managed PostgreSQL data) when the
     source removes it. The Helm-layer `helm.sh/resource-policy: keep` annotation
     the chart sets is **not** honored by Argo for its own prune decisions, so
     `Prune=false` carries the guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit — the CloudNativePG CRDs are large — and is the convention for the
     strict-B `-crds` apps.

2. The workload Application **`databases/cnpg`** at sync-wave 0, which then comes
   up against CRDs that already exist (the `postgresql.cnpg.io` API group is
   registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`databases/cnpg`.

## Regeneration / drift

The vendored manifest (`manifests/00-postgresql-cnpg-io-crds.yaml`) was generated
once from chart `cloudnative-pg` 0.28.2 via:

```sh
helm template cnpg cloudnative-pg \
  --repo https://cloudnative-pg.github.io/charts \
  --version 0.28.2 --namespace cnpg-system --skip-tests \
  --set crds.create=true \
  | yq 'select(.kind == "CustomResourceDefinition")'
```

The source chart+version (cloudnative-pg 0.28.2) is the **drift anchor**. A chart
version bump requires re-vendoring this file **and** a `databases/cnpg-crds`
version bump. It MUST be bumped **together** with the `databases/cnpg` workload
chart pin (`helm/cloudnative-pg.yaml` `version:`) — the workload chart version and
this vendored-CRD anchor are coupled (both `cloudnative-pg 0.28.2` today). No
mechanical drift check exists, consistent with the `network/multus-cni-crds`
README-only precedent; the coupling is upheld by convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because
the consumer app runs `Prune=false`, fields the upstream removes are **not**
auto-pruned from the cluster; removal needs manual intervention. A version bump is
a separate reviewed change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The `postgresql.cnpg.io` CRDs
are the API surface (schemas), not a swappable operational capability. The
swappable capability `cnpg-postgres` (managed instanced PostgreSQL) is provided by
the workload artifact `databases/cnpg` (the operator that reconciles the
`Cluster` / `Backup` / etc. CRs), not by the CRD schemas alone (precedent:
`network/multus-cni-crds`, likewise api-surface-only with the capability on its workload
counterpart). The `provides[].apis` entry pins the representative API-group surface
`postgresql.cnpg.io/Cluster@v1` (`Cluster` is the primary CRD kind).

## Sync-wave

`-1` — the CRDs land before the operator workload at wave 0, so the
`postgresql.cnpg.io` API group is registered before the operator starts
reconciling `Cluster` CRs.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/databases/cnpg-crds:vX.Y.Z
```

The git tag is `databases/cnpg-crds-vX.Y.Z` (first release `v0.1.0`); `task push`
strips the leading `v`, so the OCI registry tag is the bare SemVer. The workload
`databases/cnpg` carries `requires: {databases/cnpg-crds: ">=v0.1.0"}` and
`crds.create: false` (its companion strict-B refactor) — it renders zero CRDs and
depends on this artifact landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

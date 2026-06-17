# Component `databases/cnpg`

[CloudNativePG](https://cloudnative-pg.io) — the PostgreSQL operator for the Devoba
platform. Implements the **`cnpg-postgres`** capability (managed, instanced PostgreSQL;
`swap_class: data-migration`).

Helm chart `cloudnative-pg` from `https://cloudnative-pg.github.io/charts` (which
301-redirects to `cloudnative-pg.io/charts`), pinned to **0.28.2** (appVersion **1.29.1**).
This component ships **only the operator** — its Deployment, Service, RBAC
(`ClusterRole`/`ClusterRoleBinding`/`ServiceAccount`), and the mutating/validating
webhooks. Under the **strict-B CRD split** (ADR-0028) the `postgresql.cnpg.io` CRDs
(`Cluster`, `Backup`, `ScheduledBackup`, `Pooler`, …) ship as a **separate** artifact,
[`databases/cnpg-crds`](../cnpg-crds/) at sync-wave **-1** — this workload renders
**zero** CRDs (`crds.create: false`) and `requires` that artifact at `>=v0.1.0`.

Concrete `postgresql.cnpg.io/Cluster` CRs (for Dex, Harbor, PowerDNS, workload apps) are
**not** part of this artifact — they are consumer-owned and live in the respective app
sub-layers / consumer cluster repos.

## Freeze-line (ADR-0024)

The **workload** (operator Deployment/RBAC/webhooks) is the signed, pre-rendered
artifact (the CRDs are the companion [`databases/cnpg-crds`](../cnpg-crds/) artifact,
ADR-0028). The operator is **cluster-agnostic at the freeze line**: it needs no
consumer-supplied secrets, config files, or env to run, so `provided_refs` and every
`required.*` list are empty.

**Consumer-owned** (Layer 3), set in the consumer overlay rather than the catalog:

- **Operator HA** — `replicaCount` (single on a small lab, leader-elected HA on a control-plane cluster).
- **PodMonitor** — `monitoring.podMonitorEnabled=true` (off in the catalog default; it renders
  a `monitoring.coreos.com/PodMonitor` whose CRD is not guaranteed at sync-wave 0).
- **The `Cluster` CRs themselves** — including their database credentials — which the consumer
  authors in its own repo. Those credentials are never part of this operator artifact.

## Sync-wave

`0` — the operator (Deployment + RBAC + webhooks) starts **after** the
`postgresql.cnpg.io` CRDs are established at wave **-1** via
[`databases/cnpg-crds`](../cnpg-crds/), so the API group is registered before the
operator reconciles any consumer `Cluster` CR. The CRDs no longer ship inline with the
operator (strict-B, ADR-0028).

## Strict-B consumer wiring (ADR-0028)

This workload requires its CRDs to exist first, so the consumer cluster repo wires
**two** Argo `Application`s:

1. [`databases/cnpg-crds`](../cnpg-crds/) at `argocd.argoproj.io/sync-wave: "-1"` with
   `argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true`. `Prune=false` is
   the authoritative CR-cascade protection — it stops Argo from deleting a CRD (and
   cascading the live `Cluster`/`Backup`/`Pooler` CRs, a data-loss event) when the source
   removes it; `ServerSideApply=true` clears the 262 KB client-side annotation limit on
   the large CloudNativePG CRDs.
2. This **`databases/cnpg`** operator Application at sync-wave **0**, which comes up
   against CRDs that already exist.

**Breaking change.** Versus the previous single-artifact `databases/cnpg` (which bundled
the CRDs inline), a consumer upgrading MUST add the `databases/cnpg-crds` Application
before syncing this workload — otherwise the operator has no CRDs to reconcile.

**Version coupling.** The chart pin here (`helm/cloudnative-pg.yaml` `version: 0.28.2`)
and the `databases/cnpg-crds` vendored-CRD drift anchor (also `cloudnative-pg 0.28.2`)
MUST be bumped **together** — a chart-version bump requires re-vendoring the cnpg-crds
manifests in the same change. No mechanical drift check exists (consistent with the
`network/multus-cni-crds` precedent); the coupling is upheld by convention and review.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/databases/cnpg:cnpg-vX.Y.Z
```

## Consumed by

- A consumer with no Postgres consumer — the operator may be present with no `Cluster` CRs.
- A consumer with database workloads — consumers are Dex, Harbor, PowerDNS, and workload apps.

## Security trade-off — cluster-wide operator

`config.clusterWide: true` (chart default, pinned here) lets one operator watch
`Cluster` CRs in **every** namespace — which the multi-app consumers (Dex, Harbor,
PowerDNS) need. The cost is a broad `ClusterRole`: the operator can read/write the
PostgreSQL `Secret`s (credentials, TLS) of every CNPG `Cluster` in all namespaces.
That is the standard CNPG multi-tenant posture; a consumer running a single-tenant
or strongly-isolated cluster may instead prefer a namespace-scoped operator
(`config.clusterWide: false` + a per-namespace install) in its overlay.

## Namespace & Pod Security

The operator ships its own `cnpg-system` namespace (`manifests/00-namespace.yaml`)
with `pod-security.kubernetes.io/enforce: restricted` — cnpg is the sole occupant
(dedicated namespace), so the Namespace object travels with the artifact and a
shipped manifest wins over Argo `managedNamespaceMetadata`. `restricted` is the
strictest level the rendered operator satisfies (pod `runAsNonRoot` + seccomp
`RuntimeDefault`; container `allowPrivilegeEscalation: false` + drop `ALL` caps +
`readOnlyRootFilesystem`). Consumer-authored `Cluster` CRs run in their **own**
consumer-owned namespaces, so this level governs only the operator pods.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)

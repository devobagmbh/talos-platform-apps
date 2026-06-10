# Component `databases/cnpg`

[CloudNativePG](https://cloudnative-pg.io) — the PostgreSQL operator for the Devoba
platform. Implements the **`cnpg-postgres`** capability (managed, instanced PostgreSQL;
`swap_class: data-migration`).

Helm chart `cloudnative-pg` from `https://cloudnative-pg.github.io/charts` (which
301-redirects to `cloudnative-pg.io/charts`), pinned to **0.28.2** (appVersion **1.29.1**).
This component ships **only the operator** — its Deployment, Service, RBAC
(`ClusterRole`/`ClusterRoleBinding`/`ServiceAccount`), the mutating/validating webhooks,
and the `postgresql.cnpg.io` CRDs (`Cluster`, `Backup`, `ScheduledBackup`, `Pooler`, …).

Concrete `postgresql.cnpg.io/Cluster` CRs (for Dex, Harbor, PowerDNS, workload apps) are
**not** part of this artifact — they are consumer-owned and live in the respective app
sub-layers / consumer cluster repos.

## Freeze-line (ADR-0024)

The **workload** (operator Deployment/RBAC/webhooks + CRDs) is the signed, pre-rendered
artifact. The operator is **cluster-agnostic at the freeze line**: it needs no
consumer-supplied secrets, config files, or env to run, so `provided_refs` and every
`required.*` list are empty.

**Consumer-owned** (Layer 3), set in the consumer overlay rather than the catalog:

- **Operator HA** — `replicaCount` (single on a small lab, leader-elected HA on the seeder).
- **PodMonitor** — `monitoring.podMonitorEnabled=true` (off in the catalog default; it renders
  a `monitoring.coreos.com/PodMonitor` whose CRD is not guaranteed at sync-wave 0).
- **The `Cluster` CRs themselves** — including their database credentials — which the consumer
  authors in its own repo. Those credentials are never part of this operator artifact.

## Sync-wave

`0` — foundational substrate: it brings the `postgresql.cnpg.io` CRDs that every consuming
app's `Cluster` CR depends on, so the operator + CRDs must exist before any consumer Postgres.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/databases/cnpg:cnpg-vX.Y.Z
```

## Consumed by

- **Seeder** — no Postgres consumer currently planned.
- **office-lab** — consumers are Dex, Harbor, PowerDNS, and workload apps.

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

- [ADR-0008 — Backup-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)
- [ADR-0024 — Workload/Config-Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)

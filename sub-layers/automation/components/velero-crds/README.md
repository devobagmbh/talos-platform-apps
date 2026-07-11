# Component `automation/velero-crds`

The **strict-B CRDs artifact** (talos-platform-docs ADR-0028) for
[Velero](https://velero.io/). It ships **only** the 13 `velero.io`
CustomResourceDefinitions — the Velero operator workload (Deployment, node-agent
DaemonSet, RBAC) is a **separate** component, `automation/velero`. The two together
form the strict-B pair: CRDs first (this artifact, sync-wave -1), operator after
(sync-wave 0).

The CRDs are sourced verbatim from the upstream `velero` Helm chart **12.1.0**
(appVersion `1.18.1`). The Velero chart ships its CRDs as raw files under the
chart's `crds/` directory (NOT as `installCRDs`-gated chart templates), so this
component is delivered as **raw vendored manifests** (`kind: manifests`) extracted
once from the chart, not as a Helm reference.

## What ships

Exactly 13 cluster-scoped CustomResourceDefinitions in the `velero.io` API group:

- `backuprepositories.velero.io`
- `backups.velero.io`
- `backupstoragelocations.velero.io`
- `datadownloads.velero.io`
- `datauploads.velero.io`
- `deletebackuprequests.velero.io`
- `downloadrequests.velero.io`
- `podvolumebackups.velero.io`
- `podvolumerestores.velero.io`
- `restores.velero.io`
- `schedules.velero.io`
- `serverstatusrequests.velero.io`
- `volumesnapshotlocations.velero.io`

The served API versions are `v1` for all CRDs except the two data-mover CRDs
(`datadownloads.velero.io` and `datauploads.velero.io`), which serve `v2alpha1`.

No pods, no Services, no RBAC, no Namespace — the artifact is purely the CRD schemas.
The Velero Namespace (with its Pod Security Admission `enforce` label) stays with the
`automation/velero` workload artifact; CRDs are cluster-scoped and require no
namespace.

## Strict-B consumer wiring (ADR-0028)

The consumer cluster repo wires **two** Argo `Application`s — this `-crds` app
**before** the operator:

1. **`automation/velero-crds`** Application at `argocd.argoproj.io/sync-wave: "-1"`
   with:

   ```yaml
   argocd.argoproj.io/sync-options: Prune=false,ServerSideApply=true
   ```

   - `Prune=false` is the authoritative CR-cascade protection: it stops Argo from
     deleting a CRD (and cascading the consumer's live `Backup` / `Restore` /
     `Schedule` / `BackupStorageLocation` CRs, which would tear down backup history
     and the backup wiring) when the source removes it. The Helm-layer
     `helm.sh/resource-policy: keep` annotation is **not** honored by Argo for its
     own prune decisions, so `Prune=false` carries the guarantee.
   - `ServerSideApply=true` avoids the 262 KB client-side last-applied annotation
     limit — the Velero CRDs (notably `backups.velero.io`) are large — and is the
     convention for the strict-B `-crds` apps.

2. The workload Application **`automation/velero`** at sync-wave 0, which then comes
   up against CRDs that already exist (the `velero.io` API group is registered).

## crd-bearing pairing

This artifact carries `crd-bearing: true` in `compatibility.yaml` — the strict-B
marker and the build gate's oracle (`kind: CustomResourceDefinition` count **> 0**
here, **== 0** in the workload artifact). Its workload counterpart is
`automation/velero`.

## Regeneration / drift

The vendored manifest (`manifests/00-velero-crds.yaml`) was generated once from
chart `velero` 12.1.0 via:

```sh
helm pull velero \
  --repo https://vmware-tanzu.github.io/helm-charts \
  --version 12.1.0 --untar
# then concatenate velero/crds/*.yaml in sorted filename order.
```

The source chart+version (velero 12.1.0) is the **drift anchor**, and the 13-CRD set
is pinned to it. A chart version bump requires re-vendoring this file **and** an
`automation/velero-crds` version bump. It MUST be bumped **together** with the
`automation/velero` workload chart pin — the workload chart version and this
vendored-CRD anchor are coupled (both `velero 12.1.0` today). The exact CRD count is
brittle on chart upgrade: **re-verify the 13-CRD set** when the chart version is
bumped (a future Velero release may add or remove a CRD). No mechanical drift check
exists, consistent with the `secrets/external-secrets-crds` README-only precedent;
the coupling is upheld by convention and review.

When this artifact is bumped to a newer chart whose CRD schema changed, the
consumer's Argo sync applies the new schema in-place (ServerSideApply). Because the
consumer app runs `Prune=false`, fields the upstream removes are **not** auto-pruned
from the cluster; removal needs manual intervention. A version bump is a separate
reviewed change.

## Capability

api-surface-only, **no capability** — `capabilities: []`. The `velero.io` CRDs are
the API surface (schemas), not a swappable operational capability. The swappable
capability `backup` (Kubernetes-resource and PersistentVolume filesystem backup to an
S3-compatible target) is provided by the workload artifact `automation/velero` (the
controller Deployment + node-agent DaemonSet + RBAC that reconcile the `Backup` /
`Restore` / `Schedule` / `BackupStorageLocation` CRs), not by the CRD schemas alone
(precedent: `secrets/external-secrets-crds`, likewise api-surface-only with the
capability on its workload counterpart). The `provides[].api_surface` entries pin the
representative served surfaces — `velero.io/Backup@v1` (the primary CRD kind) through
`velero.io/DataUpload@v2alpha1` (the data-mover surface, served at `v2alpha1`).

## Sync-wave

`-1` — the CRDs land before the operator workload at wave 0, so the `velero.io` API
group is registered before the Velero controller starts reconciling `Backup` CRs.

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/velero-crds:vX.Y.Z
```

The git tag is `automation/velero-crds-vX.Y.Z` (first release `v0.1.0`); `task push`
strips the leading `v`, so the OCI registry tag is the bare SemVer. The workload
`automation/velero` carries `requires: {automation/velero-crds: ">=v0.1.0"}` and
`upgradeCRDs: false` (its companion strict-B configuration) — it renders zero CRDs
and depends on this artifact landing first at wave -1.

## Related ADRs

- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0024 — Workload/Config Freeze-Line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0008 — Backup strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)

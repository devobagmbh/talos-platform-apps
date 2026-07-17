# Component `automation/velero`

The **strict-B WORKLOAD half** (talos-platform-docs ADR-0028) of
[Velero](https://velero.io/), sourced from the upstream `vmware-tanzu/velero` Helm
chart **12.1.0** (appVersion `1.18.1`).

It ships the Velero **server Deployment**, the **node-agent DaemonSet** (filesystem
/ Kopia PodVolume backup), and the supporting **RBAC** — a `ServiceAccount`, a
`ClusterRoleBinding` to the **built-in `cluster-admin`** ClusterRole (Velero's
upstream default: the controller must read/write arbitrary resource types across
all namespaces to produce a consistent backup; the catalog ships **no** custom
ClusterRole), and a namespace-scoped `Role` + `RoleBinding` — **no
CustomResourceDefinitions**. The 13 `velero.io` CRDs are a **separate** component,
`automation/velero-crds`, wired first at sync-wave -1. The two together form the
strict-B pair: CRDs first, operator after.

The workload image is the upstream `docker.io/velero/velero:v1.18.1` (pinned, not
`:latest`); it is **not** mirrored to `ghcr.io/devobagmbh`.

This artifact renders **0 CRDs** (`upgradeCRDs: false`), no chart-default
`BackupStorageLocation` / `VolumeSnapshotLocation` (`backupsEnabled: false`,
`snapshotsEnabled: false`), and no CRD-upgrade Job.

## What ships

- Velero server `Deployment` (`velero`) + RBAC: `ServiceAccount`,
  `ClusterRoleBinding` → built-in `cluster-admin`, namespace-scoped `Role` +
  `RoleBinding`
- node-agent `DaemonSet` (`node-agent`) — Kopia PodVolume filesystem backup
- the `velero` `Namespace` (PSA `enforce: privileged`)
- NO CRDs (those are `automation/velero-crds`), no `BackupStorageLocation`,
  no `VolumeSnapshotLocation`, no `Schedule`

## Consumer obligations

This is the catalog default; cluster-specific composition is the consumer's (Layer
3). The consumer MUST:

1. **Pre-create the credential Secret.** Create a `Secret` named
   `velero-s3-credentials` in the `velero` namespace with key `cloud` holding an
   AWS-format credentials file (the catalog ships **no** credential material — Hard
   Constraint: no real secrets in the repo). It is the freeze-line
   `required.secret_keys: [cloud]` entry the workload mounts. The Secret MUST exist
   **before** this component's Argo sync: if it is absent at pod-scheduling time the
   server Deployment **and** every node-agent pod fail with `CreateContainerError`
   (Argo reports the Application `Degraded`); create the Secret and hard-refresh to
   recover.
2. **Supply the object-store plugin.** Add the `velero-plugin-for-aws`
   initContainer in the Layer-3 overlay — the catalog bakes in **none**
   (`initContainers: []`), because a versioned plugin image is a consumer-composition
   concern. Without it the server pod reports **Ready**, but every
   `BackupStorageLocation` stays in phase `Unavailable` and no backup runs — verify
   the BSL phase is `Available` after adding the initContainer and resyncing.
3. **Create the location and schedule CRs.** Author the `BackupStorageLocation`
   (S3 endpoint / bucket / region), the `VolumeSnapshotLocation`, and any `Schedule`
   CRs against the `velero.io` API surface from the `-crds` half — all Layer-3
   consumer-owned.
4. **PSA posture.** The shipped `velero` namespace carries
   `pod-security.kubernetes.io/enforce: privileged` — REQUIRED because the node-agent
   DaemonSet mounts the kubelet hostPaths (`/var/lib/kubelet/pods`,
   `/var/lib/kubelet/plugins`) and runs as root; Baseline and Restricted both forbid
   hostPath volumes, so privileged is the only admissible level.
5. **Image verification.** The workload pulls `docker.io/velero/velero:v1.18.1`
   (upstream Docker Hub, not `ghcr.io/devobagmbh`). A consumer cluster whose Kyverno
   image-verify policy targets only `ghcr.io/devobagmbh` MUST extend it to cover this
   source, or mirror the image and override `image.repository` in the Layer-3 overlay.

## Operational notes

- **Upgrade window.** The server `Deployment` uses `strategy: Recreate` (Velero's
  upstream default — it avoids two controllers racing on one `BackupStorageLocation`).
  A version upgrade therefore briefly stops the controller; a `Schedule` whose window
  falls in that gap is skipped for that cycle (Velero does not retroactively trigger a
  missed schedule). Plan upgrades outside a critical backup window.
- **Restore order (DR).** On a disaster-recovery restore, bring the pair up in
  strict-B order — `automation/velero-crds` (wave -1) → `automation/velero` (wave 0) →
  consumer `BackupStorageLocation` / `VolumeSnapshotLocation` CRs → `velero restore
  create`. The detailed DR runbook is consumer-/docs-owned (talos-platform-docs,
  ADR-0008).

## Strict-B consumer wiring (ADR-0028)

The consumer wires **two** Argo `Application`s — the `-crds` app **before** this
workload:

1. **`automation/velero-crds`** at `argocd.argoproj.io/sync-wave: "-1"` with
   `Prune=false,ServerSideApply=true`.
2. **`automation/velero`** (this artifact) at sync-wave `0`, which then comes up
   against CRDs that already exist.

## Capability

Provides the swappable operational capability **`backup`**
(`swap_class: rewrite-required`) — the controller + node-agent that reconcile the
`velero.io` CRs. The CRD schemas are the api-surface of the `-crds` half, so
`api_surface: []` here (precedent: `secrets/external-secrets`, capability on the
workload, api-surface on its `-crds` counterpart).

## Sync-wave

`0` — after the CRDs (`automation/velero-crds`, wave -1).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/automation/velero:vX.Y.Z
```

The git tag is `automation/velero-vX.Y.Z` (first release `v0.1.0`); `task push`
strips the leading `v`, so the OCI registry tag is the bare SemVer.

## Related ADRs

- [ADR-0008 — Backup strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0024 — Workload/Config freeze-line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)
- [ADR-0028 — CRD management (strict B)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0028-crd-management.md)
- [ADR-0021 — Capability layer model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)
- [ADR-0018 — Policy stack (Conftest)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0018-policy-stack.md)

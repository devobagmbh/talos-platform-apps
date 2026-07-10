# Sub-layer `storage-block`

Block-storage providers — CSI drivers that expose **block** PersistentVolumes
(as opposed to `storage-objects`, which is S3/object). The OCI distribution unit
is the component; this directory is the organisational bracket (ADR-0009).

## Components

| Component | sync-wave | Purpose |
|---|---|---|
| [`piraeus-operator-crds`](components/piraeus-operator-crds/) | -1 | Strict-B CRD half (ADR-0028) — the four `piraeus.io` Linstor CustomResourceDefinitions for the piraeus-operator. Lands before its workload counterpart. |
| [`piraeus-operator`](components/piraeus-operator/) | 0 | Strict-B workload half — the LINSTOR/DRBD operator (controller-manager + webhook + gencert); provides `block-storage-replicated` (replicated block storage). Requires `piraeus-operator-crds`. |
| [`snapshot-controller-crds`](components/snapshot-controller-crds/) | -1 | Strict-B CRD half (ADR-0028) — the 6 external-snapshotter CustomResourceDefinitions (`snapshot.storage.k8s.io` + `groupsnapshot.storage.k8s.io`) for the cluster-wide CSI snapshot machinery. Lands before its `snapshot-controller` workload counterpart. |
| [`snapshot-controller`](components/snapshot-controller/) | 0 | Strict-B workload half — the cluster-singleton external-snapshotter `snapshot-controller` Deployment (leader-election) that reconciles `VolumeSnapshot` → `VolumeSnapshotContent`. Requires `snapshot-controller-crds`. |
| [`democratic-csi`](components/democratic-csi/) | 0 | NAS-backed iSCSI block storage (Synology DSM) via democratic-csi — **Talos-native (nsenter)**; a consumer's durable tier for stateful workloads (ADR-0026) |
| [`synology-csi`](components/synology-csi/) | 0 | **DEPRECATED** — the official Synology CSI; does **not** work on Talos (iscsiadm via `chroot /host` fails — no host userland). Superseded by `democratic-csi`; kept for reference. |

## Notes

- **Talos requires democratic-csi, not synology-csi**: the official driver's node-plugin chroots into the host to run iscsiadm, which Talos has no userland for. democratic-csi nsenters into the `iscsi-tools` extension's iscsid namespace instead. Both target the same Synology NAS over iSCSI.
- Block vs object: the iSCSI CSI (PVCs) is distinct from `storage-objects/garage`
  (S3). On the Synology NAS both coexist — different access paths, same durable tier
  (ADR-0026 § Object vs Block).
- **Replicated DRBD/LINSTOR** (`block-storage-replicated`) is provided by the
  piraeus-operator strict-B pair: the CRD half (`piraeus-operator-crds`,
  sync-wave -1) and the operator workload (`piraeus-operator`, sync-wave 0). The
  consumer wires the `-crds` Argo Application first (`Prune=false`); the actual
  replicated storage is driven by consumer-authored `LinstorCluster` CRs and needs
  the DRBD kernel module on the nodes (a substrate-layer prerequisite).
- **Cluster-wide CSI snapshot machinery** is provided by the external-snapshotter
  strict-B pair: the CRD half (`snapshot-controller-crds`, sync-wave -1) ships the
  6 `snapshot.storage.k8s.io` + `groupsnapshot.storage.k8s.io` CRDs, and the
  `snapshot-controller` workload (sync-wave 0) reconciles `VolumeSnapshot` → `VolumeSnapshotContent`.
  The consumer wires the `-crds` Argo Application first (`Prune=false`); a CSI driver's
  per-driver `csi-snapshotter` sidecar (e.g. the one baked into `piraeus-operator`) and a
  consumer-authored `VolumeSnapshotClass` complete the path.

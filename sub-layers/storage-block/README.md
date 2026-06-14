# Sub-layer `storage-block`

Block-storage providers — CSI drivers that expose **block** PersistentVolumes
(as opposed to `storage-objects`, which is S3/object). The OCI distribution unit
is the component; this directory is the organisational bracket (ADR-0009).

## Components

| Component | sync-wave | Purpose |
|---|---|---|
| [`democratic-csi`](components/democratic-csi/) | 0 | NAS-backed iSCSI block storage (Synology DSM) via democratic-csi — **Talos-native (nsenter)**; a consumer's durable tier for stateful workloads (ADR-0026) |
| [`synology-csi`](components/synology-csi/) | 0 | **DEPRECATED** — the official Synology CSI; does **not** work on Talos (iscsiadm via `chroot /host` fails — no host userland). Superseded by `democratic-csi`; kept for reference. |

## Notes

- **Talos requires democratic-csi, not synology-csi**: the official driver's node-plugin chroots into the host to run iscsiadm, which Talos has no userland for. democratic-csi nsenters into the `iscsi-tools` extension's iscsid namespace instead. Both target the same DS720+ over iSCSI.
- Block vs object: the iSCSI CSI (PVCs) is distinct from `storage-objects/garage`
  (S3). On the DS720+ NAS both coexist — different access paths, same durable tier
  (ADR-0026 § Object vs Block).
- Future block providers (e.g. piraeus/LINSTOR for replicated DRBD on multi-node
  clusters) would live here as additional components.

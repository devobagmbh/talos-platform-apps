# Sub-layer `storage-block`

Block-storage providers — CSI drivers that expose **block** PersistentVolumes
(as opposed to `storage-objects`, which is S3/object). The OCI distribution unit
is the component; this directory is the organisational bracket (ADR-0009).

## Components

| Component | sync-wave | Purpose |
|---|---|---|
| [`synology-csi`](components/synology-csi/) | 0 | NAS-backed iSCSI block storage (Synology DSM); the seeder's durable tier for stateful workloads (ADR-0026) |

## Notes

- Block vs object: `synology-csi` (iSCSI PVCs) is distinct from `storage-objects/garage`
  (S3). On the DS720+ NAS both coexist — different access paths, same durable tier
  (ADR-0026 § Object vs Block).
- Future block providers (e.g. piraeus/LINSTOR for replicated DRBD on multi-node
  clusters) would live here as additional components.

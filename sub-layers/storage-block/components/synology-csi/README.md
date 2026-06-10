# Component `storage-block/synology-csi`

NAS-backed **iSCSI block-storage CSI** for the platform (SynologyOpenSource/synology-csi,
MPL-2.0). Provisions Kubernetes PVCs as iSCSI LUNs on a Synology DSM NAS, so
stateful workloads survive a node rebuild — the durable tier lives off-node.
Driving use case: the seeder's single-node Harbor (Postgres/registry) per
[ADR-0026](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0026-central-harbor-nas-block-storage.md).

## What this ships (vendored upstream `v1.3.0`, `deploy/kubernetes/v1.20`)

| Resource | Purpose |
|---|---|
| `Namespace/synology-csi` | component boundary (PSA privileged — node plugin needs host mounts) |
| `CSIDriver/csi.san.synology.com` | driver registration (attachRequired, podInfoOnMount) |
| controller `StatefulSet` + RBAC | provisioner / attacher / resizer / snapshotter sidecars |
| node `DaemonSet` + RBAC | per-node plugin + node-driver-registrar (mounts the iSCSI LUN) |
| `StorageClass/synology-iscsi-storage` | **default class**, `reclaimPolicy: Retain`, `allowVolumeExpansion: true` |

All images are pinned (driver `synology/synology-csi:v1.3.0` + `registry.k8s.io/sig-storage/*` sidecars).

## Consumer obligations (cluster-specific — not in the catalog)

1. **`client-info-secret`** in the `synology-csi` namespace (Customization Contract Shape c,
   `customization.yaml`): a SOPS Secret with key `client-info.yml` carrying the DSM
   connection (`clients: [{host, port, https, username, password}]`). The controller +
   node mount it at `/etc/synology/client-info.yml`. NO credential ships here.
2. **Talos `iscsi-tools` system extension** in the consumer's `cluster.yaml` node-class
   `extensions` (Image-Factory schematic) — without an iSCSI initiator on the node the
   driver cannot mount LUNs (ADR-0026 prerequisite).

## Scope notes

- **Minimal cut — no snapshots.** The standalone snapshot controller + `VolumeSnapshotClass`
  are intentionally NOT shipped (they need the external-snapshotter CRDs, a separate
  concern). PVC provision/attach/resize — Harbor's actual need — works without them.
  The controller's `csi-snapshotter` sidecar is present but idle until the snapshot CRDs
  exist; add them + the snapshotter as a follow-on if VolumeSnapshots are needed.
- **Sidecar age / k8s compatibility.** The upstream `v1.20` manifest set pins older
  sig-storage sidecars (provisioner v3.0.0 …). Verify against the target Kubernetes at
  deploy; bump the sidecar tags in a follow-on if a newer cluster needs it.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-block/synology-csi:<tag>
```

## References

- ADR-0026 (central Harbor + NAS block storage via synology-csi)
- upstream: <https://github.com/SynologyOpenSource/synology-csi> (MPL-2.0)

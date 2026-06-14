# `storage-block/democratic-csi`

NAS-backed iSCSI block storage via **[democratic-csi](https://github.com/democratic-csi/democratic-csi)** (`synology-iscsi` driver) against the Synology DS720+ — a consumer's durable tier for stateful workloads (ADR-0026). Provides the default StorageClass `synology-iscsi-storage`.

- **OCI path:** `ghcr.io/devobagmbh/talos-platform-apps/storage-block/democratic-csi`
- **sync-wave:** `0` (storage substrate — Ready before stateful consumers like harbor, wave 30)
- **Chart:** `democratic-csi/democratic-csi` `0.15.1`, rendered to static manifests

## Why democratic-csi (not the official synology-csi) on Talos

The official `synology/synology-csi` node-plugin runs iscsiadm via `chroot /host`, which **cannot work on Talos** — the host rootfs has no userland (`/usr/bin/env`, no iscsiadm). Sidero closed that as "not planned". The portable Talos pattern is **`nsenter` into the iscsi-tools extension's iscsid namespace**, which democratic-csi supports as a first-class config (`ISCSIADM_HOST_STRATEGY=nsenter`). See `helm/democratic-csi.yaml` `node.driver.extraEnv`.

> The `synology-iscsi` driver is upstream-marked **experimental** — verify the LUN type / DSM compatibility against the DS720+ during the pilot.

## Talos prerequisite

The node image must carry the **`siderolabs/iscsi-tools`** system extension (provides `/usr/local/sbin/iscsiadm` + the `ext-iscsid` service). It is bootstrap-baked via the consumer `cluster.yaml` (`classes.<class>.extensions`) and the Image-Factory schematic — a re-provision is required to add it.

## Consumer contract (ADR-0024 Shape c)

The catalog ships **no credentials**. The consumer supplies a Secret `synology-iscsi-driver-config` (key `driver-config-file.yaml`) with the full democratic-csi driver config — DSM `httpConnection` (host/port/username/password) + `iscsi` (targetPortal, lunTemplate). Referenced via `driver.existingConfigSecret`; the chart emits only the reference, never the values. See `customization.yaml`.

## Contents

| File | Role |
|---|---|
| `helm/democratic-csi.yaml` | chart ref + Talos values (csiDriver, storageClasses, node nsenter, existingConfigSecret) |
| `manifests/00-namespace.yaml` | `democratic-csi` namespace, PSA `privileged` (node needs hostPID + privileged mounts) |
| `customization.yaml` | consumer contract — the `synology-iscsi-driver-config` secret |
| `compatibility.yaml` | provides `democratic-csi@0.15.1` |

## Related ADRs

- **ADR-0026** — single central Harbor + NAS block storage; the CSI choice for the durable tier.

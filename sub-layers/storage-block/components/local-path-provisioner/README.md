# Component `storage-block/local-path-provisioner`

Node-local **block-storage** provisioner (Rancher local-path-provisioner,
Apache-2.0). Dynamically provisions `hostPath`-backed PersistentVolumes from a
directory on the node, so a workload that needs fast node-local storage (and does
not need to survive a node loss) gets a PVC without an external storage backend.
Implements the `block-storage-local` capability (ADR-0021). Based verbatim on the
upstream `v0.0.36` manifest with two Talos overlays (node path + helper-image
pin).

## What this ships (upstream `v0.0.36`, `deploy/local-path-storage.yaml`)

| Resource | Purpose |
|---|---|
| `Namespace/local-path-storage` | component boundary (PSA `privileged` — helper Pod mounts a hostPath) |
| `ServiceAccount/local-path-provisioner-service-account` | controller identity |
| `Role` + `RoleBinding` (`local-path-provisioner-*`) | namespace-scoped pod management (helper Pods) |
| `ClusterRole` + `ClusterRoleBinding` (`local-path-provisioner-*`) | cluster-scoped PV/PVC/node/storageclass access |
| `Deployment/local-path-provisioner` | the provisioner controller (replicas: 1) |
| `StorageClass/local-path` | `provisioner: rancher.io/local-path`, `WaitForFirstConsumer`, `reclaimPolicy: Delete` — **non-default** by design |
| `ConfigMap/local-path-config` | `config.json` (node path map) + `setup`/`teardown` scripts + `helperPod.yaml` template |

Images (both pinned):

- provisioner: `docker.io/rancher/local-path-provisioner:v0.0.36`
- helper Pod (in `helperPod.yaml`): `docker.io/library/busybox:1.37.0@sha256:9532d8c39891ca2ecde4d30d7710e01fb739c87a8b9299685c63704296b16028`

The helper image is pinned to an immutable digest rather than a floating tag. The
conftest `no_latest_image_tag` policy does **not** scan ConfigMap data, so this
pin is enforced by manifest content + review, not by a gate — it is recorded here
so a future bump is a deliberate, reviewed change.

## Talos overlays (vs. upstream)

1. **Node path** — `config.json` `nodePathMap` points at
   `/var/mnt/local-path-provisioner`, not the upstream `/opt/local-path-provisioner`
   (`/opt` is read-only on Talos).
2. **Helper-image digest pin** — see above.

## Consumer obligations (substrate — not in the catalog)

1. **Talos `UserVolumeConfig` machineconfig** mounting a disk/partition at
   `/var/mnt/local-path-provisioner` on every node that should serve local-path
   PVs, applied via the base/substrate layer **before** this component syncs.
   Without a writable, persistent directory there, provisioning fails. This is a
   substrate concern (machineconfig), out of scope for this component, and is why
   `customization.yaml` carries no `provided_refs` shape.
2. **Default-class opt-in (optional)** — the `StorageClass/local-path` is shipped
   **non-default** on purpose; making it the cluster default is a consumer choice.
   Add the `storageclass.kubernetes.io/is-default-class: "true"` annotation in the
   consumer overlay if desired.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/storage-block/local-path-provisioner:<tag>
```

sync-wave `0` (storage substrate — Ready before stateful consumers).

## References

- [ADR-0024](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-customization-contract.md) (customization contract / freeze-line)
- [ADR-0021](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md) (capability model — `block-storage-local`)
- upstream: <https://github.com/rancher/local-path-provisioner> (Apache-2.0)

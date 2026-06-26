# Sub-layer `storage-objects`

Garage as an S3-compatible object store for tf-state, iPXE images, LGTM-A backends, Velero source, and app buckets.

OCI distribution per component (ADR-0009).

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`garage-crds`](components/garage-crds/) | -1 | `GarageNode` CRD (strict-B CRD half, ADR-0028) | `oci://.../storage-objects/garage-crds:vX.Y.Z` |
| [`garage`](components/garage/) | 0 | Helm `garage` 0.9.3 (vendored, appVersion v2.3.0) | `oci://.../storage-objects/garage:vX.Y.Z` |
| [`garage-buckets`](components/garage-buckets/) | 10 | Bucket + key provisioning via the Garage admin API v2 (consumer-supplied keys, ESO-synced) | `oci://.../storage-objects/garage-buckets:vX.Y.Z` |

Wave -1 establishes the `GarageNode` CRD (strict-B CRD half), wave 0 provides the S3 endpoint, wave 10 the bucket definitions (bucket + access key via ESO from Vault).

## Consumed by

- A single-node consumer — single-node cluster. Buckets: `tf-state`, `ipxe`, `velero-source-<consumer>`
- A multi-node consumer — 3-node cluster. Buckets: `mimir-blocks`, `loki-chunks`, `tempo-blocks`, `harbor-store`, `velero-source-<consumer>`, app-specific buckets
- **DS720+** — a separate Garage cluster (Docker container on a NAS, NOT a member of the K8s clusters). Tier-2 backup target with buckets `velero-<consumer>` (one per source cluster). Backup invariant: target ≠ source.

## Backlog issue

[#13 — Sub-layer `storage-objects/`: Garage](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects)

Related: [#7.5 — DS720+ container setup](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DS720%2B), [#40 — Tier-1/2 backup-path validation](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Backup-Pfade)

## Related ADRs

- [ADR-0007 — Platform-Object-Store (Garage chosen)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0008 — Backup-Strategy (DS720+/Garage as tier-2)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

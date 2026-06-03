# Sub-Layer `storage-objects`

Garage als S3-kompatibler Object-Store für tf-state, iPXE-Images, LGTM-A-Backends, Velero-Source und App-Buckets.

OCI-Distribution pro Komponente (ADR-0009).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`garage`](components/garage/) | 0 | Helm `deuxfleurs/garage` (oder custom) | `oci://.../storage-objects/garage:vX.Y.Z` |
| [`garage-buckets`](components/garage-buckets/) | 10 | Bucket-CRs + ESO-Access-Key-Sync | `oci://.../storage-objects/garage-buckets:vX.Y.Z` |

Wave 0 stellt den S3-Endpoint, Wave 10 die Bucket-Definitionen (Bucket + Access-Key via ESO aus Vault).

## Konsumiert von

- **Seeder** — Single-Node-Cluster. Buckets: `tf-state`, `ipxe`, `velero-source-seeder`
- **Office-Lab** — 3-Node-Cluster. Buckets: `mimir-blocks`, `loki-chunks`, `tempo-blocks`, `harbor-store`, `velero-source-office-lab`, App-spezifische Buckets
- **DS720+** — separates Garage-Cluster (Docker-Container auf NAS, KEIN Mitglied der K8s-Cluster). Tier-2-Backup-Ziel mit Buckets `velero-seeder`, `velero-office-lab`. Backup-Invariante: Ziel ≠ Quelle.

## Backlog-Issue

[#13 — Sub-Layer `storage-objects/`: Garage](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects)

Verwandt: [#7.5 — DS720+-Container-Setup](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DS720%2B), [#40 — Tier-1/2-Backup-Pfade-Validierung](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Backup-Pfade)

## Verwandte ADRs

- [ADR-0007 — Platform-Object-Store (Garage gewählt)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0008 — Backup-Strategy (DS720+/Garage als Tier-2)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

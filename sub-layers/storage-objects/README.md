# Sub-Layer `storage-objects`

Garage als S3-kompatibler Object-Store für tf-state, iPXE-Images, LGTM-A-Backends, Velero-Source und App-Buckets.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| Garage | Helm `deuxfleurs/garage` (oder custom-chart) | S3-kompatibler Object-Store, ZFS-Block-Storage via Linstor |
| Garage-Bucket-Manager | dieses Repo | `Bucket`-CR-Definitionen + Access-Key-Generierung via ESO/Vault |

## Konsumiert von

- **Seeder** — Single-Node-Garage-Cluster. Buckets: `tf-state` (Stage-1-State), `ipxe` (Talos-Images), `velero-source-seeder` (Backup-Output, von Velero auf DS720+ ge-rsynct).
- **DHQ** — Multi-Node-Garage-Cluster über 3 Nodes. Buckets: `mimir-blocks`, `loki-chunks`, `tempo-blocks`, `harbor-store`, `velero-source-dhq`, App-spezifische Buckets.
- **DS720+** — Separates Garage-Cluster (Docker-Container auf NAS, KEIN Mitglied von Seeder- oder DHQ-Cluster). Zweck: Tier-2-Backup-Ziel. Buckets: `velero-seeder`, `velero-dhq`. Backup-Invariante: Ziel ≠ Quelle.

## Inhalt

- `helm/garage.yaml` — Defaults (Replication-Faktor, Compaction-Schedule, Listener)
- `manifests/buckets/<name>.yaml` — pro Bucket: Definition + Access-Key-Generation (via ESO + Vault-Engine `kv-v2`)
- `manifests/cnpg-not-required.md` — Hinweis: Garage hat keine externe DB, eigener Metadata-Store
- `scripts/restic-init.sh` — Helfer für Velero-Restic-Repo-Initialisierung in den DS720+-Buckets

## Backlog-Issue

[#13 — Sub-Layer `storage-objects/`: Garage](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+storage-objects)

Verwandt: [#1 ✓ — S3-Backup-Ziel-Entscheidung (DS720+/Garage in Docker)](https://github.com/devobagmbh/talos-platform-docs/issues/1), [#7.5 — DS720+-Container-Setup](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DS720%2B), [#40 — Tier-1/2-Backup-Pfade-Validierung](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Backup-Pfade).

## Verwandte ADRs

- [ADR-0007 — Platform-Object-Store (Garage gewählt)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0007-platform-object-store.md)
- [ADR-0008 — Backup-Strategy (DS720+/Garage als Tier-2)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0008-backup-strategy.md)
- [ADR-0006 — TF-State-Management (Garage als Stage-1-Backend)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)

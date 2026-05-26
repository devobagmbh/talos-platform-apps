# Sub-Layer `registry`

Harbor als Container-/OCI-Registry mit Pull-Through-Cache und OCI-Artefakt-Support.

OCI-Distribution pro Komponente (ADR-0009).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`harbor`](components/harbor/) | 0 | Helm `harbor/harbor` (inkl. Trivy-Subchart) | `oci://.../registry/harbor:vX.Y.Z` |

Cross-Sub-Layer-Abhängigkeiten: braucht `databases/cnpg` (Postgres) und `storage-objects/garage` (S3-Bucket).

## Konsumiert von

- **Seeder** — als Pull-Through-Cache vor GHCR/Docker-Hub
- **DHQ** — als eigener Workload-Registry

Beide Cluster betreiben Harbor unabhängig.

## Backlog-Issues

- [#14 — Sub-Layer `registry/`: Harbor](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+registry)
- [#27 — Seeder-Harbor konfigurieren (OIDC + Pre-Warm)](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Seeder-Harbor)
- [#33 — DHQ-Harbor mit CNPG-Postgres](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-Harbor)

## Verwandte ADRs

- [ADR-0012 — Platform-Registry-Proxy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-Cluster-Registry](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

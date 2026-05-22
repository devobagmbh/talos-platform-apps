# Sub-Layer `registry`

Harbor als Container-/OCI-Registry mit Pull-Through-Cache und OCI-Artefakt-Support.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| Harbor | Helm `harbor/harbor` | Container-Registry + Pull-Through-Cache + OCI-Artefakt-Store (Helm-Charts, cosign, SBOMs, CNAB) |
| Trivy-Scanner | als Harbor-Sub-Chart | Vulnerability-Scanning für Images im Cluster |

## Konsumiert von

- **Seeder** — als Pull-Through-Cache vor GHCR/Docker-Hub. Verkürzt PXE-Boots, reduziert Outbound-Traffic, ermöglicht Air-Gap-Phasen.
- **DHQ** — als eigener Workload-Registry für interne Devoba-Apps + Mirror-Cache.

Beide Cluster betreiben Harbor unabhängig (eigene Postgres, eigener Garage-Bucket-Store). Konsistenz zwischen den beiden ist nicht garantiert — DHQ-Harbor kann auf Seeder-Harbor als upstream-Proxy zeigen, falls Bandbreite zum Internet eingeschränkt ist.

## Inhalt

- `helm/harbor.yaml` — Werte (Postgres via CNPG, Storage via Garage S3, OIDC via Dex)
- `manifests/postgres-cluster.yaml` — `CNPG.Cluster` für Harbor-DB
- `manifests/garage-bucket.yaml` — Bucket-Definition (oder Verweis ins `storage-objects`-Sub-Layer)
- `manifests/oidc-config.yaml` — OIDC-Provider-Connector zu Dex

## Backlog-Issues

- [#14 — Sub-Layer `registry/`: Harbor](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+registry)
- [#27 — Seeder-Harbor konfigurieren (OIDC + Pre-Warm)](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Seeder-Harbor)
- [#33 — DHQ-Harbor mit CNPG-Postgres](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-Harbor)

## Verwandte ADRs

- [ADR-0012 — Platform-Registry-Proxy (Harbor auf Seeder)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-Cluster-Registry (Harbor auf beiden Clustern)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)

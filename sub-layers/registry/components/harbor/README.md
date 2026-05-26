# Komponente `registry/harbor`

Harbor (Helm `harbor/harbor`) — Container-Registry + Pull-Through-Cache + OCI-Artefakt-Store (Helm-Charts, cosign, SBOMs, CNAB). Inkl. Trivy-Scanner als Subchart. Postgres via CNPG, Storage via Garage S3, OIDC via Dex.

**Skelett** — Implementation in Issues [#14](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+registry), [#27](https://github.com/devobagmbh/talos-platform-apps/issues/?q=Seeder-Harbor), [#33](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-Harbor).

## Sync-Wave

`0` — kein Inter-Komponenten-Dependency innerhalb des Sub-Layers. Cross-Sub-Layer-requires (CNPG + Garage) werden durch ihre eigenen sync-waves in den Konsumenten-Cluster-Manifests behandelt.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/registry/harbor:vX.Y.Z
```

## Konsumiert von

- **Seeder** — als Pull-Through-Cache vor GHCR/Docker-Hub
- **DHQ** — als eigener Workload-Registry für interne Devoba-Apps

Beide Cluster betreiben Harbor unabhängig (eigene Postgres, eigener Garage-Bucket-Store).

## Verwandte ADRs

- [ADR-0012 — Platform-Registry-Proxy (Harbor auf Seeder)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-Cluster-Registry (Harbor auf beiden Clustern)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)

# Komponente `registry/harbor`

Harbor (Helm `harbor/harbor` 1.19.1, appVersion 2.15.1) — Container-Registry + Pull-Through-Cache + OCI-Artefakt-Store. Inkl. Trivy-Scanner.

## Render-Profil (Tag 1: Seeder-Pull-Through-Cache)

Das aktuell gerenderte Profil ist für den **Seeder** ausgelegt (Single-Node, eine Platte, kein Linstor):

- **Storage: ephemeral** (`persistence.enabled: false`) — für einen Cache vertretbar, baut sich neu auf.
- **DB + Redis: eingebettet** (`type: internal`) — kein CNPG, kein Garage-S3 (garage obsolet).
- **Exposure: clusterIP**, TLS extern am Cilium-Gateway (Gateway-API-only Hard-Constraint, kein Ingress).
- **Auth: db_auth** (admin) — OIDC via Dex wird nachgereicht.
- **Secrets** (ADR-0023): admin-Passwort + `secretKey` via `existingSecret: harbor-runtime-secret` (Konsument liefert via SOPS). Interne Service-Secrets generiert Harbor (Rotation bei ephemeral Cache unkritisch).
- **externalURL**: Platzhalter `https://REPLACE-ME.harbor.invalid` → Konsument patcht via Kustomize (Klasse-A-Strukturwert).

Das persistente **office-lab-Harbor-Profil** (PVC/CNPG + stabile interne Secrets via Vault) bekommt einen eigenen Render. Customization-Vertrag: [`customization.yaml`](customization.yaml).

## Sync-Wave

`0` — kein Inter-Komponenten-Dependency innerhalb des Sub-Layers. Cross-Sub-Layer-requires (CNPG + Garage) werden durch ihre eigenen sync-waves in den Konsumenten-Cluster-Manifests behandelt.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/registry/harbor:vX.Y.Z
```

## Konsumiert von

- **Seeder** — als Pull-Through-Cache vor GHCR/Docker-Hub
- **office-lab** — als eigener Workload-Registry für interne Devoba-Apps

Beide Cluster betreiben Harbor unabhängig (eigene Postgres, eigener Garage-Bucket-Store).

## Verwandte ADRs

- [ADR-0012 — Platform-Registry-Proxy (Harbor auf Seeder)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0012-platform-registry-proxy.md)
- [ADR-0013 — In-Cluster-Registry (Harbor auf beiden Clustern)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0013-in-cluster-registry.md)

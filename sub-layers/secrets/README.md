# Sub-Layer `secrets`

External-Secrets-Operator (ESO) als Sync-Mechanismus zwischen Vault (Layer 3, cluster-spezifisch) und Kubernetes-Workloads.

## Layer-Zuordnung

Dieser Sub-Layer ist **Schicht 2 (Modulkatalog)** und enthält ausschließlich den ESO-Operator + ESO-Defaults. **Vault-Cluster-Instance, Policies und KV-Pfade leben in Schicht 3 (`talos-office-lab-cluster`)**, nicht hier. Damit bleibt der Modulkatalog frei von cluster-Identität und Vault-Konsumenten-Spezifika.

Siehe [ADR-0011 Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md) für die Two-Lane-Begründung (SOPS = Cluster-Maintenance, Vault = Workload-Secrets).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`cert-manager`](components/cert-manager/) | 0 | Helm `cert-manager` @ jetstack v1.20.2 — TLS-Issuance-Controller + CRDs | `oci://.../secrets/cert-manager:vX.Y.Z` |
| [`external-secrets`](components/external-secrets/) | 0 | Helm `external-secrets/external-secrets` | `oci://.../secrets/external-secrets:vX.Y.Z` |
| [`clustersecretstore-defaults`](components/clustersecretstore-defaults/) | 10 | Boilerplate-Manifeste | `oci://.../secrets/clustersecretstore-defaults:vX.Y.Z` |
| [`ca-clusterissuer`](components/ca-clusterissuer/) | 20 | cert-manager CA-`ClusterIssuer`, CA-Key via ESO aus Vault | `oci://.../secrets/ca-clusterissuer:vX.Y.Z` |

Wave 0 bringt die CRDs (`ExternalSecret`, `ClusterSecretStore`). Wave 10 die default `ClusterSecretStore`-Resources `vault-local` (Office-Lab) und `vault-office-lab-remote` (Seeder); konkrete Vault-Endpoints werden in Layer 3 überschrieben. Wave 20 den CA-`ClusterIssuer`, der TLS-Leaf-Certs für `*.office-lab.devoba.de` aus der Devoba-eigenen CA signiert (CA-Root via Jamf in den Client-Trust ausgerollt; Planungsupdate 2026-05-27 — ersetzt den entfallenen `dns`-Sub-Layer mit ACME-DNS01).

**Nicht in diesem Sub-Layer**: Vault-Helm-Release, Vault-Policies, Vault-KV-Strukturen, Vault-Auth-Method-Config.

## Konsumiert von

- **Seeder** — `external-secrets` + cross-cluster `ClusterSecretStore: vault-office-lab-remote` (AppRole/JWT-Auth zu Office-Lab-Vault)
- **Office-Lab** — `external-secrets` + lokaler `ClusterSecretStore: vault-local` (Kubernetes-Auth)

Stage-0-Seeder-Bootstrap nutzt **kein** ESO — nur SOPS (siehe ADR-0011).

## Backlog-Issues

- [#15a — Sub-Layer `secrets/`: ESO + ClusterSecretStore-Defaults](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets)
- [#32 — Office-Lab-Vault-HA Setup](https://github.com/devobagmbh/talos-platform-docs/issues/36) — gehört in `talos-office-lab-cluster`, nicht hier

## Verwandte ADRs

- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0010 — Identity-Provider (Vault-OIDC-Auth via Dex)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

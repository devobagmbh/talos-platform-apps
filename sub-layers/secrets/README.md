# Sub-Layer `secrets`

External-Secrets-Operator (ESO) als Sync-Mechanismus zwischen Vault (Layer 3, cluster-spezifisch) und Kubernetes-Workloads.

## Layer-Zuordnung

Dieser Sub-Layer ist **Schicht 2 (Modulkatalog)** und enthält ausschließlich den ESO-Operator + ESO-Defaults. **Vault-Cluster-Instance, Policies und KV-Pfade leben in Schicht 3 (`talos-dhq-cluster`)**, nicht hier. Damit bleibt der Modulkatalog frei von cluster-Identität und Vault-Konsumenten-Spezifika.

Siehe [ADR-0011 Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md) für die vollständige Two-Lane-Begründung (SOPS = Cluster-Maintenance, Vault = Workload-Secrets).

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| ESO | Helm `external-secrets/external-secrets` | `ExternalSecret`/`ClusterSecretStore`-CRDs — synct Secrets aus Vault in K8s-Secrets |
| ClusterSecretStore-Defaults | dieses Repo | Boilerplate für `vault-local` (DHQ) und `vault-dhq-remote` (Seeder); konkrete Vault-Endpoints werden in Layer 3 überschrieben |

**Nicht in diesem Sub-Layer**: Vault-Helm-Release, Vault-Policies, Vault-KV-Strukturen, Vault-Auth-Method-Config. Diese gehören in das Konsumenten-Repo (`talos-dhq-cluster/secrets/`, Layer 3).

## Konsumiert von

- **Seeder** — ESO + `ClusterSecretStore: vault-dhq-remote` (cross-cluster zu DHQ-Vault via AppRole/JWT-Auth). Für Seeder-Workloads, die Vault-Secrets brauchen (z. B. Cross-AM-Webhook-BasicAuth).
- **DHQ** — ESO + `ClusterSecretStore: vault-local` (lokale Vault-Cluster via Kubernetes-Auth-Backend).

Stage-0-Seeder-Bootstrap nutzt **kein** ESO — nur SOPS (siehe ADR-0011, Cluster-Maintenance-Lane).

## Inhalt

- `helm/external-secrets.yaml` — Operator-Werte (Defaults, Service-Account, RBAC)
- `manifests/clustersecretstore-defaults.yaml` — Boilerplate für `vault-local` und `vault-dhq-remote`; konkrete Endpoints + Auth-Refs werden im Konsumenten-Repo überschrieben

## Backlog-Issues

- [#15a — Sub-Layer `secrets/`: ESO + ClusterSecretStore-Defaults](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets)
- [#32 — DHQ-Vault-HA Setup](https://github.com/devobagmbh/talos-platform-docs/issues/36) — gehört in `talos-dhq-cluster`, nicht hier

## Verwandte ADRs

- [ADR-0011 — Secrets-Management (5-Recipient-SOPS + Layer-3-Vault)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0010 — Identity-Provider (Vault-OIDC-Auth via Dex)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)

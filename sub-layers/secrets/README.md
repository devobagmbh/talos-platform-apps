# Sub-Layer `secrets`

External-Secrets-Operator (ESO) + Vault-Config-Templates für die Runtime-Lane der Two-Lane-Secrets-Architektur.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| ESO | Helm `external-secrets/external-secrets` | `ExternalSecret`/`ClusterSecretStore`-CRDs → synct Secrets aus Vault in K8s-Secrets |
| Vault-Helm | Helm `hashicorp/vault` | (nur DHQ) Vault-Cluster, 3-Replica Raft, integriertes Storage |
| Vault-Config-Templates | dieses Repo | Auth-Methods (k8s, oidc), Policies, Engines (kv-v2, pki, database), Sealed-/Unsealed-Init-Manifeste |

## Konsumiert von

- **Seeder** — ESO konsumiert DHQ-Vault über cross-cluster-`ClusterSecretStore` (mTLS + scoped Token).
- **DHQ** — Vault-Cluster + ESO. Alle anderen Sub-Layer konsumieren Vault-Secrets über ESO.

## Inhalt

- `helm/vault.yaml` — HA-Konfig (Raft, 3 Replicas), Auto-Unseal disabled (manueller Shamir-Unseal nach ADR-0011), TLS-Listener
- `helm/external-secrets.yaml` — Operator-Werte
- `manifests/clustersecretstore-vault.yaml` — Default-Store zu DHQ-Vault (im Seeder cross-cluster-spezifisch)
- `manifests/vault-config-bootstrap.yaml` — Job-basiertes Bootstrap der Policies + Auth-Methods (Idempotent)
- `manifests/policies/` — Vault-Policies pro Konsumenten-Klasse (cert-manager, dex, harbor, powerdns, ai-agent)

Hinweis: Initial-Vault-Init (Generieren der Shamir-Shards) ist NICHT automatisiert — siehe [RB-03 vault-unseal.md](https://github.com/devobagmbh/talos-platform-docs/blob/main/runbooks/vault-unseal.md) und [Issue #32](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-Vault-HA).

## Backlog-Issues

- [#15a — Sub-Layer `secrets/`: ESO + Vault Config-Templates](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets)
- [#32 — DHQ-Vault-HA: Init + Unseal + Konfigurieren](https://github.com/devobagmbh/talos-platform-apps/issues/?q=DHQ-Vault-HA)

## Verwandte ADRs

- [ADR-0011 — Secrets-Management (Two-Lane: 4-Key-SOPS + Vault)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0010 — Identity-Provider (Vault-OIDC-Auth via Dex)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)

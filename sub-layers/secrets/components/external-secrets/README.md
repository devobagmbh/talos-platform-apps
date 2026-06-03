# Komponente `secrets/external-secrets`

External-Secrets-Operator (Helm `external-secrets/external-secrets`) — `ExternalSecret`-/`ClusterSecretStore`-CRDs. Synct Secrets aus Vault (Layer 3) in K8s-Secrets.

**Skelett** — Implementation in Issue [#15a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets).

## Sync-Wave

`0` — bringt die CRDs.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/external-secrets:vX.Y.Z
```

## Konsumiert von

- **Seeder** — ja (cross-cluster zu Office-Lab-Vault via AppRole/JWT)
- **Office-Lab** — ja (lokale Vault-Cluster via Kubernetes-Auth)

Stage-0-Seeder-Bootstrap nutzt **kein** ESO — nur SOPS.

## Verwandte ADRs

- [ADR-0011 — Secrets-Management (5-Recipient-SOPS + Layer-3-Vault)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)

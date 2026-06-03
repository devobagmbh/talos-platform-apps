# Komponente `secrets/clustersecretstore-defaults`

Boilerplate für `ClusterSecretStore`-Resources: `vault-local` (Office-Lab) und `vault-office-lab-remote` (Seeder, cross-cluster). Konkrete Vault-Endpoints + Auth-Refs werden im Konsumenten-Cluster-Repo (Layer 3) überschrieben.

**Skelett** — Implementation in Issue [#15a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets).

**Nicht in diesem Sub-Layer**: Vault-Helm-Release, Vault-Policies, Vault-KV-Strukturen, Vault-Auth-Method-Config — die gehören ins Konsumenten-Repo (Layer 3).

## Sync-Wave

`10` — braucht `secrets/external-secrets` (CRD `ClusterSecretStore`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/clustersecretstore-defaults:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)

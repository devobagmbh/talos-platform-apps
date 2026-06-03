# Component `secrets/external-secrets`

External Secrets Operator (Helm `external-secrets/external-secrets`, chart 2.5.0)
— installs the ESO operator + all CRDs (`external-secrets.io` + the
`generators.external-secrets.io` group). Syncs secrets from Vault (Layer 3) into
Kubernetes Secrets, and — via the **generators** — mints/refreshes provider
tokens.

`installCRDs: true` brings the full CRD set, **including `GithubAccessToken`** —
the generator the seeder uses to mint/refresh the private-GHCR pull credential
without a PAT ([ADR-0025](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)).

## Contents

- `helm/external-secrets.yaml` — ESO chart reference + slim default values.

## Sync-wave

`0` here (catalog default — brings the CRDs). A consumer that depends on ESO at
bootstrap (e.g. the seeder's GHCR token) deploys it in an **earlier** wave
(the seeder uses `-10`) so ESO is up before the components that need it.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/external-secrets:vX.Y.Z
```

## Consumed by

- **Seeder** — yes: the GHCR `GithubAccessToken` generator (ADR-0025) + later
  cross-cluster `ClusterSecretStore` to the office-lab Vault.
- **office-lab** — yes: local Vault `ClusterSecretStore` (Kubernetes auth).

The Stage-0 seeder bootstrap does **not** use ESO — only SOPS (+ the one-shot
GHCR token mint bridges until ESO is up).

## Related ADRs

- [ADR-0011 — Secrets-Management (SOPS + Layer-3 Vault)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0025 — ArgoCD-Credentials ohne PAT (GithubAccessToken generator)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0025-argocd-credentials-no-pat.md)

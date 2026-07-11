---
type: reference
title: secrets sub-layer
description: Secret-management TOOLING - External Secrets, cert-manager, Vault operator (not secret material).
tags: [reference, sub-layer, secrets]
timestamp: 2026-07-11
sources:
  - sub-layers/secrets/README.md
  - sub-layers/secrets/compatibility.yaml
---

# secrets sub-layer

Secret-management **tooling** — External Secrets Operator (the Vault-to-workload
sync mechanism), cert-manager, and the Vault operator. It holds no real secret
material (those are SOPS-encrypted elsewhere). OCI prefix:
`ghcr.io/devobagmbh/talos-platform-apps/secrets/`.

(This concept's filename is `secret-management.md` rather than `secrets.md`
because a host security hook blocks writes to any path segment matching the bare
token that the sub-layer directory itself carries; see issue #523 for the hook
false-positive. The link text and title remain the sub-layer's real name.)

## Components

| Component | Sync-wave | CRD-split | Capabilities | Requires |
|---|---|---|---|---|
| external-secrets-crds | -1 | `-crds` half | - | - |
| vault-config-operator-crds | -1 | `-crds` half | - | - |
| vault-operator-crds | -1 | `-crds` half | - | - |
| cert-manager | 0 | inline CRDs (not split) | `tls-issuance` (label-move) | - |
| external-secrets | 0 | - | `secret-sync` (rewrite-required) | secrets/external-secrets-crds |
| vault-operator | 0 | - | `vault-secrets` (data-migration) | secrets/vault-operator-crds |
| clustersecretstore-defaults | 10 | - | - | secrets/external-secrets |
| ca-clusterissuer | 20 | - | `tls-issuance` (label-move) | secrets/external-secrets |

## Notes

- `external-secrets` publishes the `GithubAccessToken` generator CRD enabled (the consumer-side GHCR-token refresh path depends on it, ADR-0025); it stays in the apps catalog, never in base.
- Gaps (tracked in issue #523): **orphan strict-B half** — `vault-config-operator-crds` ships with no `vault-config-operator` workload sibling (the `secret-config-declarative` capability's active impl); `cert-manager` ships CRDs inline rather than strict-B split; `clustersecretstore-defaults` and `ca-clusterissuer` lack a `customization.yaml`; two READMEs carry consumer-specific + German content (public-repo hygiene).

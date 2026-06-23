# Sub-layer `secrets`

External Secrets Operator (ESO) as the sync mechanism between Vault (layer 3, cluster-specific) and Kubernetes workloads.

## Layer assignment

This sub-layer is **layer 2 (module catalog)** and contains only the ESO operator + ESO defaults. **The Vault cluster instance, policies, and KV paths live in layer 3 (`<consumer-repo>`)**, not here. This keeps the module catalog free of cluster identity and Vault-consumer specifics.

See [ADR-0011 Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md) for the two-lane rationale (SOPS = cluster maintenance, Vault = workload secrets).

## Components

| Component | sync-wave | Source | OCI |
|---|---|---|---|
| [`external-secrets-crds`](components/external-secrets-crds/) | -1 | The 23 ESO CRDs (strict-B `-crds` half, ADR-0028) vendored from chart 2.5.0 | `oci://.../secrets/external-secrets-crds:vX.Y.Z` |
| [`cert-manager`](components/cert-manager/) | 0 | Helm `cert-manager` @ jetstack v1.20.2 — TLS issuance controller + CRDs | `oci://.../secrets/cert-manager:vX.Y.Z` |
| [`external-secrets`](components/external-secrets/) | 0 | Helm `external-secrets/external-secrets` — CRD-free ESO operator (strict-B workload half; requires `external-secrets-crds`) | `oci://.../secrets/external-secrets:vX.Y.Z` |
| [`clustersecretstore-defaults`](components/clustersecretstore-defaults/) | 10 | Boilerplate manifests | `oci://.../secrets/clustersecretstore-defaults:vX.Y.Z` |
| [`ca-clusterissuer`](components/ca-clusterissuer/) | 20 | cert-manager CA `ClusterIssuer`, CA key via ESO from Vault | `oci://.../secrets/ca-clusterissuer:vX.Y.Z` |

Wave -1 brings the ESO CRDs (`ExternalSecret`, `ClusterSecretStore`, …) — the separate `external-secrets-crds` artifact, which the consumer wires at sync-wave -1 with `Prune=false,ServerSideApply=true` (ADR-0028 strict-B). Wave 0 brings the CRD-free ESO operator (`external-secrets`) plus the cert-manager controller. Wave 10 the default `ClusterSecretStore` resources `vault-local` (in-cluster Vault consumer) and `vault-office-lab-remote` (cross-cluster Vault consumer); concrete Vault endpoints are overridden in layer 3. Wave 20 the CA `ClusterIssuer`, which signs TLS leaf certs for `*.office-lab.devoba.de` from the Devoba-owned CA (CA root rolled out into the client trust via Jamf; planning update 2026-05-27 — replaces the dropped `dns` sub-layer with ACME-DNS01).

**Not in this sub-layer**: Vault Helm release, Vault policies, Vault KV structures, Vault auth-method config.

## Consumed by

- A consumer with a remote Vault — `external-secrets` + cross-cluster `ClusterSecretStore: vault-office-lab-remote` (AppRole/JWT auth to the remote Vault)
- A consumer with an in-cluster Vault — `external-secrets` + local `ClusterSecretStore: vault-local` (Kubernetes auth)

The stage-0 bootstrap uses **no** ESO — only SOPS (see ADR-0011).

## Backlog issues

- [#15a — Sub-layer `secrets/`: ESO + ClusterSecretStore defaults](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+secrets)
- [#32 — Vault HA setup](https://github.com/devobagmbh/talos-platform-docs/issues/36) — belongs in `<consumer-repo>`, not here

## Related ADRs

- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0010 — Identity-Provider (Vault OIDC auth via Dex)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

# Component `secrets/ca-clusterissuer`

cert-manager `ClusterIssuer` of type **CA** that holds an operator-owned CA and signs leaf certificates for the cluster domain (`*.<cluster-domain>`).

**Skeleton** — implementation in the TLS issue.

## Background (planning update 2026-05-27)

TLS no longer runs via Let's Encrypt / DNS01-ACME, but via an **operator-owned CA**:

- The CA **root** is rolled out into the operator's client system trust stores via the operator's device-management (MDM) tooling — browsers/CLIs then trust every `*.<cluster-domain>` certificate.
- Inside the cluster this `ClusterIssuer` signs the leaf certs from the CA key. Structurally identical to the local mkcert setup (`local/mkcert-cluster-issuer.yaml`), only with the real operator CA.
- DNS is served by the site network (wildcard → cluster ingress VIP) — no in-cluster DNS server, no External-DNS, no DNS01 solver. The former `dns` sub-layer is dropped entirely.

## CA-key provenance

The CA key (`ca.crt` + `ca.key`) is sensitive material and does **not** belong in this repo. It is synced via ESO (`secrets/external-secrets`) from Vault (Layer 3) into a Secret the `ClusterIssuer` references. This component ships only the `ClusterIssuer` resource + the `ExternalSecret` template; the concrete Vault path is cluster-specific (consumer repo).

## Sync-wave

`20` — needs `secrets/external-secrets` (CRDs + a running operator that pulls the CA key from Vault) and cert-manager (from base).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/ca-clusterissuer:vX.Y.Z
```

## Related ADRs

- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- ADR-0019 — TLS via own CA (MDM-distributed) *(new)*

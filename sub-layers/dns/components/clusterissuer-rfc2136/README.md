# Komponente `dns/clusterissuer-rfc2136`

cert-manager-`ClusterIssuer` mit RFC2136-Solver gegen PowerDNS. Erlaubt DNS01-basierte TLS-Cert-Issuance für `*.dhq.devoba.de`.

**Skelett** — Implementation in Issue [#16a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+dns).

## Sync-Wave

`20` — braucht aktiven PowerDNS (Wave 0) und das TSIG-Secret (über `secrets/external-secrets` aus Vault).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/dns/clusterissuer-rfc2136:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0017 — External-DNS-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)
- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)

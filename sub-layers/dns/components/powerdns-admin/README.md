# Komponente `dns/powerdns-admin`

PowerDNS-Admin (community Helm-Chart) — Web-UI zur Zone-Verwaltung, OIDC via Dex.

**Skelett** — Implementation in Issue [#16a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+dns).

## Sync-Wave

`10` — braucht `dns/powerdns` (API + DB).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/dns/powerdns-admin:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0017 — External-DNS-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)
- [ADR-0010 — Identity-Provider](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0010-identity-provider.md)

# Komponente `dns/powerdns`

PowerDNS-Auth-Server (Helm `powerdns/pdns` oder custom) — autoritativer DNS-Server für `dhq.devoba.de`, Master für DS720+-Slave-AXFR. Inkl. CNPG-`Cluster`-CR fürs Postgres-Backend.

**Skelett** — Implementation in Issue [#16a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+dns).

## Sync-Wave

`0` — bildet das API-Backend für `powerdns-admin`, `external-dns` und den DNS01-Solver.

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/dns/powerdns:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0017 — External-DNS-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)
- [ADR-0011 — Secrets-Management (TSIG via Vault+ESO)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)

# Sub-Layer `dns`

PowerDNS-Auth + External-DNS + cert-manager-DNS01-Issuer für die `dhq.devoba.de`-Zone.

## Komponenten

| Komponente | Quelle | Funktion |
|---|---|---|
| PowerDNS-Auth | Helm `powerdns/pdns` (oder custom) | autoritativer DNS-Server für `dhq.devoba.de`, Master für DS720+-Slave-AXFR |
| PowerDNS-Admin | Helm community-chart | Web-UI zur Zone-Verwaltung |
| External-DNS | Helm `kubernetes-sigs/external-dns` | Watcher für `HTTPRoute`/`Gateway`-Ressourcen → PowerDNS-API-Updates |
| cert-manager-DNS01-Issuer | Manifest | `ClusterIssuer` mit RFC2136-Solver gegen PowerDNS für TLS-Cert-Issuance |

## Konsumiert von

- **Seeder** — nein. Seeder hat keinen autoritativen DNS-Bedarf (DS720+ ist Primary für `seeder.devoba.de`).
- **DHQ** — ja, ab Phase 6 (siehe [Issue #38a](https://github.com/devobagmbh/talos-platform-docs/issues/?q=Phase-6+DHQ-PowerDNS+deploy)).

## Inhalt

- `helm/powerdns.yaml` — Auth-Server-Konfig (CNPG-DB-Backend, AXFR-allow-from DS720+, TSIG-Keys, API-Token via ESO)
- `helm/external-dns.yaml` — RFC2136-Provider-Konfig (TSIG-Key über ESO aus Vault)
- `helm/powerdns-admin.yaml` — Web-UI-Werte, OIDC via Dex
- `manifests/clusterissuer-rfc2136.yaml` — cert-manager-Issuer-Setup mit TSIG-Secret-Referenz
- `manifests/postgres-cluster.yaml` — `CNPG.Cluster` für PowerDNS-Backend

## Backlog-Issue

[#16a — Sub-Layer `dns/`](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+dns)

## Verwandte ADRs

- [ADR-0017 — External-DNS-Strategy (DHQ-PowerDNS Master, DS720+ Slave)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)
- [ADR-0011 — Secrets-Management (TSIG-Key-Verteilung über Vault+ESO)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0014 — Load-Balancer-Strategy (Gateway-API-VIPs)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0014-load-balancer-strategy.md)

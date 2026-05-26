# Sub-Layer `dns`

PowerDNS-Auth + External-DNS + cert-manager-DNS01-Issuer für die `dhq.devoba.de`-Zone.

OCI-Distribution pro Komponente (ADR-0009).

## Komponenten

| Komponente | sync-wave | Quelle | OCI |
|---|---|---|---|
| [`powerdns`](components/powerdns/) | 0 | Helm `powerdns/pdns` + CNPG-`Cluster` | `oci://.../dns/powerdns:vX.Y.Z` |
| [`powerdns-admin`](components/powerdns-admin/) | 10 | Helm community-chart, OIDC via Dex | `oci://.../dns/powerdns-admin:vX.Y.Z` |
| [`external-dns`](components/external-dns/) | 10 | Helm `kubernetes-sigs/external-dns`, RFC2136 | `oci://.../dns/external-dns:vX.Y.Z` |
| [`clusterissuer-rfc2136`](components/clusterissuer-rfc2136/) | 20 | Manifest, cert-manager-`ClusterIssuer` | `oci://.../dns/clusterissuer-rfc2136:vX.Y.Z` |

Sync-Reihenfolge: PowerDNS (Wave 0) bringt API + DB → Admin/External-DNS (Wave 10) lesen/schreiben → ClusterIssuer (Wave 20) braucht beides + TSIG-Secret aus Vault via ESO.

## Konsumiert von

- **Seeder** — nein (DS720+ ist Primary für `seeder.devoba.de`)
- **DHQ** — ja, ab Phase 6 ([Issue #38a](https://github.com/devobagmbh/talos-platform-docs/issues/?q=Phase-6+DHQ-PowerDNS+deploy))

## Backlog-Issue

[#16a — Sub-Layer `dns/`](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+dns)

## Verwandte ADRs

- [ADR-0017 — External-DNS-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)
- [ADR-0011 — Secrets-Management (TSIG-Key-Verteilung über Vault+ESO)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0014 — Load-Balancer-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0014-load-balancer-strategy.md)
- [ADR-0009 — Platform-Layer-Model](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0009-platform-layer-model.md)

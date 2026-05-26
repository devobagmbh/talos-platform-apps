# Komponente `dns/external-dns`

External-DNS (Helm `kubernetes-sigs/external-dns`) — Watcher für `HTTPRoute`/`Gateway`-Ressourcen, schreibt RFC2136-Updates an PowerDNS. TSIG-Key kommt über ESO aus Vault.

**Skelett** — Implementation in Issue [#16a](https://github.com/devobagmbh/talos-platform-apps/issues/?q=sub-layer+dns).

## Sync-Wave

`10` — braucht `dns/powerdns` (RFC2136-Endpoint) und `secrets/external-secrets` (TSIG-Sync).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/dns/external-dns:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0017 — External-DNS-Strategy](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0017-external-dns-strategy.md)

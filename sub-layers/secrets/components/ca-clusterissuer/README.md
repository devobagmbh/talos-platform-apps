# Komponente `secrets/ca-clusterissuer`

cert-manager-`ClusterIssuer` vom Typ **CA**, der die Devoba-eigene CA hält und Leaf-Zertifikate für `*.dhq.devoba.de` (bzw. die jeweilige Cluster-Domain) signiert.

**Skelett** — Implementation im TLS-Issue.

## Hintergrund (Planungsupdate 2026-05-27)

TLS läuft **nicht** mehr über Let's-Encrypt / DNS01-ACME, sondern über eine **eigene CA**:

- Die CA-**Root** wird via **Jamf** in den System-Trust der Devoba-Clients (Macs) ausgerollt — Browser/CLI vertrauen damit allen `*.dhq.devoba.de`-Zertifikaten.
- Im Cluster signiert dieser `ClusterIssuer` die Leaf-Certs aus dem CA-Key. Strukturell identisch zum lokalen mkcert-Setup (`local/mkcert-cluster-issuer.yaml`), nur mit der echten Devoba-CA.
- DNS kommt von Unifi (Wildcard → Cluster-Ingress-VIP) — kein In-Cluster-DNS-Server, kein External-DNS, kein DNS01-Solver. Der frühere `dns`-Sub-Layer entfällt komplett.

## CA-Key-Herkunft

Der CA-Key (`ca.crt` + `ca.key`) ist sensibles Material und gehört **nicht** in dieses Repo. Er wird via ESO (`secrets/external-secrets`) aus Vault (Layer 3) in ein Secret synchronisiert, das der `ClusterIssuer` referenziert. Diese Komponente liefert nur die `ClusterIssuer`-Resource + das `ExternalSecret`-Template; der konkrete Vault-Pfad ist cluster-spezifisch (Konsumenten-Repo).

## Sync-Wave

`20` — braucht `secrets/external-secrets` (CRDs + laufenden Operator, der den CA-Key aus Vault zieht) und cert-manager (aus base).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/ca-clusterissuer:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0011 — Secrets-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- ADR-0019 — TLS via eigene CA (Jamf-verteilt) *(neu)*

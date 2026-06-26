# Component `secrets/ca-clusterissuer`

A cert-manager `ClusterIssuer` of type **CA**. It holds the Devoba-owned CA and
signs leaf certificates for the cluster domain (e.g. `*.office-lab.devoba.de`).

## What ships

The signed catalog workload (`rendered/manifest.yaml`) contains **exactly one**
resource: a cert-manager `ClusterIssuer` named `ca-clusterissuer` whose
`spec.ca.secretName` is the fixed, catalog-owned name `ca-key-pair`. Consumers
reference the issuer via the `cert-manager.io/cluster-issuer: ca-clusterissuer`
annotation on their `Certificate` CRs.

The CR is cluster-agnostic — the same rendered manifest ships unchanged to every
consumer. It carries no consumer-specific values and **no real key material**
(Hard Constraint: no real secrets in this repo). It ships **no** `Namespace`
object (the CA Secret lives in cert-manager's own namespace, a foreign namespace
this component does not declare) and **no** `ExternalSecret` (consumer-owned glue,
see below).

## Background (planning update 2026-05-27)

TLS no longer runs via Let's Encrypt / DNS01-ACME but via an **own CA**:

- The CA **root** is rolled out into the system trust of Devoba clients (Macs) via
  **Jamf**, so browsers and CLIs trust every `*.office-lab.devoba.de` certificate.
- Inside the cluster, this `ClusterIssuer` signs the leaf certs from the CA key.
- DNS comes from Unifi (wildcard -> cluster ingress VIP) — there is no in-cluster
  DNS server, no External-DNS, and no DNS01 solver.

## Consumer obligation

The CA key pair is sensitive material and is **not** part of this repo or the OCI
artifact. The consumer **MUST** populate a `kubernetes.io/tls` Secret named
`ca-key-pair` in the `cert-manager` namespace with keys `tls.crt` and `tls.key`
**before** the `ClusterIssuer` reconciles (sync-wave 20). cert-manager reads that
Secret from its own (cluster-resource) namespace; a namespace mismatch is a
**silent runtime failure** — there is no admission error.

`cert-manager` itself is **base substrate** (`talos-platform-base`), a co-equal
input the consumer integrates — never an apps catalog dependency. The
`ClusterIssuer` CRD therefore comes from base and **MUST** exist before
sync-wave 20.

### ExternalSecret example template (consumer-owned, NOT shipped/signed)

The recommended mechanism to satisfy the obligation is an ExternalSecret that
pulls the CA cert and key from Vault. This template is **README-only** — it is not
rendered, not signed, and not part of the OCI artifact. Its `secretStoreRef.name`
and `remoteRef.key` values are consumer-supplied (cluster-specific) and belong in
the consumer cluster repo:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ca-key-pair
  namespace: cert-manager # cert-manager default namespace; MUST match consumer's actual cert-manager namespace
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: <consumer-supplied> # e.g. vault-backend
  target:
    name: ca-key-pair
    template:
      type: kubernetes.io/tls
  data:
    - secretKey: tls.crt
      remoteRef:
        key: <consumer-supplied> # Vault KV path to CA cert
    - secretKey: tls.key
      remoteRef:
        key: <consumer-supplied> # Vault KV path to CA private key
```

## Sync-wave

`20` — requires `secrets/external-secrets` (the running ESO operator that
populates the CA Secret), `secrets/external-secrets-crds` (the `ExternalSecret`
CRD source), and cert-manager (from base, for the `ClusterIssuer` CRD).

## OCI

```text
oci://ghcr.io/devobagmbh/talos-platform-apps/secrets/ca-clusterissuer:vX.Y.Z
```

## Related ADRs

- [ADR-0011 — Secrets management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0011-secrets-management.md)
- [ADR-0019 — TLS via own CA (Jamf-distributed)](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0019-tls-own-ca.md)
- [ADR-0024 — Workload/Config freeze-line](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0024-workload-config-freeze-line.md)

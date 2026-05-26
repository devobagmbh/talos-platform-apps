# Komponente `lifecycle/providers`

Crossplane-Provider-Pakete für die DHQ-Provisionierungs-Pipeline.

| Provider | Version | Zweck |
|---|---|---|
| `provider-terraform` | v0.20.0 | wrappt OpenTofu für Talos-Provisioning |
| `provider-helm` | v0.20.0 | bootstrappt Cilium/Linstor/Argo nach Cluster-Up |
| `provider-kubernetes` | v0.18.0 | post-bootstrap K8s-Manifeste |

## Inhalt

- `manifests/providers.yaml` — drei `Provider`-CRs, Versionen gepinnt.

## Sync-Wave-Position

`sync-wave: "10"` — braucht `lifecycle/crossplane` (CRD `pkg.crossplane.io/Provider`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/providers:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)

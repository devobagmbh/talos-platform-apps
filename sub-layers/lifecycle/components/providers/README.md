# Komponente `lifecycle/providers`

Crossplane-Provider-Pakete für die Office-Lab-Provisionierungs-Pipeline.

| Provider | Version | Zweck |
|---|---|---|
| `provider-terraform` | v0.20.0 | wrappt OpenTofu für Talos-Provisioning |
| `provider-helm` | v0.20.0 | bootstrappt Cilium/Linstor/Argo nach Cluster-Up |
| `provider-kubernetes` | v0.18.0 | post-bootstrap K8s-Manifeste |

> **Namensklarstellung:** `provider-terraform` (API-Group `tf.upbound.io/v1beta1`) ist
> der Upstream-Eigenname des Crossplane-Providers `upbound/provider-terraform` — er führt
> intern **OpenTofu** aus. Das Tooling-Mandat des Ökosystems ist OpenTofu (ADR-0004); der
> `terraform`-Bestandteil in Provider-Paket-, API-Group- und `terraform-provider-talos`-
> Namen ist Upstream-Nomenklatur, **kein Terraform-Einsatz und kein offener
> Migrations-Rest**.

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

# Komponente `lifecycle/providers`

Crossplane-Provider- **und Function**-Pakete für die Child-Cluster-Provisionierung (z. B. office-lab).

| Paket | Kind | Version | Zweck |
|---|---|---|---|
| `provider-terraform` | Provider | v0.20.0 | wrappt OpenTofu für Talos-Provisioning (der einzige von der xcluster-Composition genutzte Provider) |
| `provider-kubernetes` | Provider | v0.18.0 | optional/post-bootstrap K8s-Manifeste ins Child (falls nicht via base-inlineManifest) |
| `function-patch-and-transform` | Function | v0.8.2 | **Pflicht** für Pipeline-Mode: mappt XCluster-spec → Workspace-varmap |
| `function-auto-ready` | Function | v0.4.2 | **Pflicht**: leitet XCluster-Ready aus dem Workspace ab |

`provider-helm` wurde **entfernt**: Cilium/ArgoCD kommen nicht mehr als nachgelagertes `helm.crossplane.io/Release`, sondern als Talos-`inlineManifest` beim Child-Bootstrap (base v0.7.0 `deploy_argocd` + Cilium-Recipe). Die xcluster-Composition ist dadurch ein reiner tofu-Workspace.

## Inhalt

- `manifests/providers.yaml` — zwei `Provider`-CRs + zwei `Function`-CRs, Versionen gepinnt.

## Sync-Wave-Position

`sync-wave: "10"` — braucht `lifecycle/crossplane` (CRD `pkg.crossplane.io/Provider`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/providers:vX.Y.Z
```

## Verwandte ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)

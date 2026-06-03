# Component `lifecycle/providers`

Crossplane provider **and function** packages for child-cluster provisioning (e.g. office-lab).

| Package | Kind | Version | Purpose |
|---|---|---|---|
| `provider-terraform` | Provider | v0.20.0 | wraps OpenTofu for Talos provisioning (the only provider used by the xcluster Composition) |
| `provider-kubernetes` | Provider | v0.18.0 | optional/post-bootstrap K8s manifests into the child (if not delivered via base inlineManifest) |
| `function-patch-and-transform` | Function | v0.8.2 | **mandatory** for Pipeline mode: maps XCluster spec → Workspace varmap |
| `function-auto-ready` | Function | v0.4.2 | **mandatory**: derives XCluster Ready from the Workspace |

`provider-helm` was **removed**: Cilium/ArgoCD no longer arrive as a downstream `helm.crossplane.io/Release`, but as a Talos `inlineManifest` at child bootstrap (base v0.7.0 `deploy_argocd` + Cilium recipe). The xcluster Composition is therefore a pure tofu Workspace.

## Contents

- `manifests/providers.yaml` — two `Provider` CRs + two `Function` CRs, versions pinned.

## Sync-wave position

`sync-wave: "10"` — requires `lifecycle/crossplane` (CRD `pkg.crossplane.io/Provider`).

## OCI

```
oci://ghcr.io/devobagmbh/talos-platform-apps/lifecycle/providers:vX.Y.Z
```

## Related ADRs

- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
- [ADR-0006 — TF-State-Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
